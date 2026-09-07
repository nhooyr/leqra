"""v2.4 room UX and join-or-create regression tests. Optional Playwright tooling only.
Run against the app, or --isolated with TestBrowserFixture (TESTING.md).
Isolated mode injects the shipped assets, provides a synthetic URL/storage,
and uses real WebSockets to the test-only local Go server.
"""
import argparse
import json
import re
import secrets
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('url', nargs='?', default='http://localhost:8080')
parser.add_argument('--isolated', action='store_true')
parser.add_argument('--browser', default=None)
parser.add_argument('--output', default='test-output/room-features')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'web'
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
checks, errors = [], []


def check(condition, label):
    assert condition, label
    checks.append(label)
    print('PASS', label, flush=True)


def state(page):
    return page.evaluate('leqra.getState()')


def connected(page):
    page.wait_for_function('leqra.getState().online?.connected', timeout=10000)


def names(page):
    return [p['name'] for p in state(page)['online']['players']]


with sync_playwright() as pw:
    options = {'headless': True}
    if args.browser:
        options['executable_path'] = args.browser
    browser = pw.chromium.launch(**options)
    contexts = []

    def load(query='', name=None, session=None, size=(1365, 950), blocked_storage=False):
        mobile = size[0] < 760 or size[1] < 620
        context = browser.new_context(viewport={'width': size[0], 'height': size[1]},
                                      is_mobile=mobile, has_touch=mobile,
                                      device_scale_factor=2 if mobile else 1)
        contexts.append(context)
        page = context.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        url = args.url.rstrip('/') + '/' + query
        setup = r"""window.__sockets=[];window.__sent=[];window.__messages=[];
const RealSocket=window.WebSocket;
window.WebSocket=class extends RealSocket{
 constructor(...a){super(...a);window.__sockets.push(this);this.addEventListener('message',e=>window.__messages.push(JSON.parse(e.data)))}
 send(value){window.__sent.push(JSON.parse(value));return super.send(value)}
};"""
        if args.isolated:
            # about:blank has an opaque origin; storage emulation is test-only.
            setup += r"""
function memoryStorage(initial){const data={...initial};return {
 getItem:k=>Object.prototype.hasOwnProperty.call(data,k)?data[k]:null,
 setItem:(k,v)=>{data[k]=String(v)}, removeItem:k=>{delete data[k]},clear:()=>{for(const k in data)delete data[k]}
};}
"""
            local = {'leqra.name': name} if name is not None else {}
            tab = {'leqra.session': json.dumps(session)} if session else {}
            setup += f"Object.defineProperty(window,'localStorage',{{configurable:true,value:memoryStorage({json.dumps(local)})}});"
            setup += f"Object.defineProperty(window,'sessionStorage',{{configurable:true,value:memoryStorage({json.dumps(tab)})}});"
            if blocked_storage:
                setup += "for(const storage of [localStorage,sessionStorage])for(const key of ['getItem','setItem','removeItem'])storage[key]=()=>{throw new Error('Storage disabled by test')};"
            html = root.joinpath('index.html').read_text()
            html = re.sub(r'<link[^>]*>', '', html)
            html = html.replace('<script src="game.js" defer></script>', '').replace('<script src="netcode.js" defer></script>', '')
            html = html.replace('</head>', '<style>' + root.joinpath('style.css').read_text() + '</style></head>')
            page.set_content(html)
            page.evaluate('()=>{' + setup + '}')
            js = root.joinpath('game.js').read_text().replace('(() => {', '((location) => {', 1)
            pos = js.rfind('})();')
            js = js[:pos] + f'}})(new URL({json.dumps(url)}));' + js[pos+5:]
            page.add_script_tag(content=root.joinpath('netcode.js').read_text())
            page.add_script_tag(content=js)
        else:
            if name is not None:
                setup += f"localStorage.setItem('leqra.name',{json.dumps(name)});"
            if session:
                setup += f"sessionStorage.setItem('leqra.session',{json.dumps(json.dumps(session))});"
            if blocked_storage:
                setup += "for(const key of ['getItem','setItem','removeItem'])Storage.prototype[key]=()=>{throw new Error('Storage disabled by test')};"
            page.add_init_script(setup)
            page.goto(url)
        page.wait_for_function('window.leqra')
        return page

    def own_name(page, expected):
        page.wait_for_function('name=>leqra.getState().online?.players.some(p=>p.id===leqra.getState().online.id&&p.name===name)', arg=expected)

    def rename(page, value, prefix='room', enter=False):
        page.locator(f'#{prefix}Callsign').fill(value)
        if enter:
            page.locator(f'#{prefix}Callsign').press('Enter')
        else:
            page.locator(f'#{prefix}CallsignForm button').click()

    def create(name='HOST'):
        page = load(name=name)
        page.locator('[data-mode=online]').click()
        page.locator('#createRoomBtn').click()
        connected(page)
        return page, state(page)['online']['code']

    host, code = create()
    before = state(host)['online']
    rename(host, 'HOST NEW')
    own_name(host, 'HOST NEW')
    check(state(host)['online']['id'] == before['id'] and state(host)['online']['code'] == code,
          'Lobby rename preserves seat and room')
    check(host.evaluate("localStorage.getItem('leqra.name')") == 'HOST NEW', 'Server-approved callsign saved on device')
    check(host.evaluate("JSON.parse(sessionStorage.getItem('leqra.session')).name") == 'HOST NEW', 'Reconnect storage uses renamed callsign')

    layouts = [(1365, 950), (390, 844), (320, 568), (844, 390)]
    phone = load('?room=' + code.lower(), name='RAIN', size=layouts[1]); connected(phone)
    tiny = load('?room=' + code, size=layouts[2]); connected(tiny)
    wide = load('?room=' + code, name='WIDE', size=layouts[3]); connected(wide)
    players = [host, phone, tiny, wide]
    own_name(phone, 'RAIN'); own_name(tiny, 'PILOT')
    check(phone.locator('#roomScreen').is_visible() and 'RAIN' in names(phone), 'Lowercase invite automatically joins with saved callsign')
    check(tiny.locator('#roomScreen').is_visible() and 'PILOT' in names(tiny), 'New visitor joins invite directly as PILOT')
    check(all(p.evaluate('__sent.filter(m=>m.type==="join").length') == 1 for p in players[1:]), 'Invite opens exactly one joining connection per fresh visitor')
    for i, page in enumerate(players):
        page.wait_for_function('leqra.getState().online.players.length===4')
        check('HOST NEW' in names(page), f'Renamed host visible to client {i+1}')
        check(page.evaluate('document.documentElement.scrollWidth<=innerWidth'), f'No horizontal overflow {layouts[i]}')
        colors = page.evaluate("['createRoomBtn','joinRoomBtn'].map(id=>{const s=getComputedStyle(document.getElementById(id));return [s.backgroundColor,s.color,s.borderTopColor]})")
        check(colors[0] == colors[1], f'Join and Create Room share colors {layouts[i]}')
        check(page.locator('#startRoomBtn').evaluate('e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1'), f'Room start action fits vertically {layouts[i]}')
        page.screenshot(path=str(out / f'room-{layouts[i][0]}x{layouts[i][1]}.png'))

    # A room broadcast must not overwrite someone halfway through typing.
    phone.locator('#roomCallsign').fill('DRAFT NAME')
    host.locator('#readyBtn').click()
    phone.wait_for_function('leqra.getState().online.players[0].ready')
    check(phone.locator('#roomCallsign').input_value() == 'DRAFT NAME', 'Ready update does not clobber callsign draft')
    rename(phone, '  Rain Fox  ', enter=True)
    own_name(phone, 'Rain Fox')
    host.wait_for_function('leqra.getState().online.players.some(p=>p.name==="Rain Fox")')
    check('Rain Fox' in names(host), 'Enter saves callsign and broadcasts to other pilots')
    rename(phone, '<>😈')
    phone.wait_for_function('document.getElementById("roomCallsignStatus").classList.contains("error")')
    check('Rain Fox' in names(phone), 'Invalid rename shows error and preserves previous name')
    check(state(phone)['online']['connected'], 'Invalid callsign does not disconnect pilot')
    rename(phone, 'RAIN AGAIN'); own_name(phone, 'RAIN AGAIN')
    check(phone.locator('#roomCallsign').input_value() == 'RAIN AGAIN', 'Callsign can be changed repeatedly')

    # Fill all four seats and verify error handling does not loop.
    full = load('?room=' + code)
    full.wait_for_function('document.getElementById("netStatus").classList.contains("error")')
    check('seats' in full.locator('#netStatus').inner_text().lower(), 'Full invite returns useful error without manual join step')
    check(full.evaluate('__sent.filter(m=>m.type==="join").length') == 1, 'Full room does not trigger endless auto-join retries')
    full.close()

    for page in players[1:]: page.locator('#readyBtn').click()
    host.locator('#startRoomBtn').click()
    for page in players: page.wait_for_function('leqra.getState().phase==="playing"')
    host.locator('#pauseBtn').click()
    before = state(host)
    rename(host, 'Fierce Falcon', prefix='menu', enter=True)
    own_name(host, 'Fierce Falcon')
    phone.wait_for_function('leqra.getState().tanks.some(t=>t.name==="Fierce Falcon")')
    after = state(host)
    check(after['online']['serverTick'] > before['online']['serverTick'], 'Match keeps advancing while editing callsign')
    check(after['online']['id'] == before['online']['id'] and after['scores'] == before['scores'], 'In-match rename preserves tank identity and score')
    check('Fierce Falcon' in names(phone), 'In-match rename reaches remote room and tank labels')
    host.screenshot(path=str(out / 'in-match-callsign.png'))
    host.locator('#onlineReturnBtn').click()

    # Refresh-equivalent: dispose page/socket, then boot shipped client with same session.
    session = wide.evaluate("JSON.parse(sessionStorage.getItem('leqra.session'))")
    old_id = state(wide)['online']['id']; wide.close()
    host.wait_for_function('id=>leqra.getState().online.players.some(p=>p.id===id&&!p.connected)', arg=old_id)
    resumed = load('?room=' + code, name='STALE LOCAL', session=session, size=layouts[3]); connected(resumed)
    check(state(resumed)['online']['id'] == old_id and len(names(resumed)) == 4, 'Invite with live reconnect credential resumes seat instead of duplicating it')
    check(resumed.locator('#menuCallsign').input_value() == 'WIDE', 'Resume restores authoritative name over stale local name')
    resumed.locator('#pauseBtn').click()
    rename(resumed, 'WIDE NEW', prefix='menu'); own_name(resumed, 'WIDE NEW')
    check(resumed.locator('#onlineLeaveBtn').evaluate('e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1'), 'Landscape match menu keeps Leave room visible after saving')
    resumed.screenshot(path=str(out / 'landscape-callsign-menu.png'))
    check(resumed.locator('#menuCallsignForm button').is_enabled() is False, 'Saved callsign disables redundant Save action')

    # Separate room allows stale or copied credentials to fall back without taking
    # over an active pilot. Initial links take priority over unrelated sessions.
    host2, code2 = create('SECOND HOST')
    stale = {'code': code2, 'token': 'expired-token', 'name': 'STALE PILOT', 'at': int(time.time()*1000)}
    retry = load('?room=' + code2, session=stale); connected(retry)
    check('STALE PILOT' in names(retry), 'Expired invite resume token falls back to a fresh seat')
    sent = retry.evaluate('__sent.filter(m=>m.type==="join")')
    check(len(sent) == 2 and 'token' in sent[0] and 'token' not in sent[1], 'Expired-token fallback uses one fresh join, not a reconnect loop')
    copied_session = retry.evaluate("JSON.parse(sessionStorage.getItem('leqra.session'))")
    copied = load('?room=' + code2, session=copied_session); connected(copied)
    check(state(copied)['online']['id'] != state(retry)['online']['id'] and state(retry)['online']['connected'], 'Copied-tab invitation joins separately without replacing active pilot')
    # An old session for another room must not intercept the explicit invitation.
    different = load('?room=' + code2, name='EXPLICIT', session=session); connected(different)
    check(state(different)['online']['code'] == code2 and 'EXPLICIT' in names(different), 'Explicit invite takes priority over another room saved in session')

    # Named creation and normal joins share one backend transaction. Use fresh
    # codes so these checks can be re-run without restarting the test server.
    def fresh_code():
        return ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))

    named_code = fresh_code()
    missing = load('?room=' + named_code.lower(), name='INVITE HOST'); connected(missing)
    own_name(missing, 'INVITE HOST')
    check(state(missing)['online']['code'] == named_code, 'Missing invite creates exactly the requested room code')
    check('HOST' in missing.locator('#roomCallsignForm label').inner_text(), 'Missing invite makes its first pilot the host')
    check(missing.evaluate('__messages.find(m=>m.type==="welcome").created===true'), 'Creator welcome identifies newly created room')
    check(missing.evaluate('__sent.filter(m=>m.type==="join").length===1 && !__sent.some(m=>m.type==="create")'), 'Missing invite joins and creates in one request, without a random-code fallback')
    check(missing.locator('#startRoomBtn').is_disabled(), 'Auto-created host still needs another ready pilot')
    follower = load('?room=' + named_code, name='FOLLOWER'); connected(follower)
    missing.wait_for_function('leqra.getState().online.players.length===2')
    check(state(follower)['online']['code'] == named_code and state(follower)['online']['id'] != state(missing)['online']['id'], 'Next visitor joins the same room as a guest')
    check('HOST' in missing.locator('#roomCallsignForm label').inner_text() and 'HOST' not in follower.locator('#roomCallsignForm label').inner_text(), 'Existing-room invite preserves the original host')
    check(follower.evaluate('__messages.find(m=>m.type==="welcome").created===false'), 'Existing-room visitor does not report another creation')
    check(missing.locator('#roomRoster [data-kick-target]').count() == 1, 'Automatically assigned host receives kick controls')
    missing.locator('#readyBtn').click(); follower.locator('#readyBtn').click()
    missing.wait_for_function('!document.querySelector("#startRoomBtn").disabled')
    missing.locator('#startRoomBtn').click()
    follower.wait_for_function('leqra.getState().phase==="playing"')
    check(state(missing)['phase'] == 'playing', 'Auto-created room starts a normal server-authoritative match')

    typed_code = fresh_code()
    typed = load(name='TYPED HOST', size=layouts[2])
    typed.locator('[data-mode=online]').click()
    typed.locator('#joinCode').fill(typed_code.lower())
    typed.locator('#joinCode').press('Enter'); connected(typed); own_name(typed, 'TYPED HOST')
    check(state(typed)['online']['code'] == typed_code and 'HOST' in typed.locator('#roomCallsignForm label').inner_text(), 'Typing a missing code and pressing Enter creates a room and assigns host')
    check(typed.locator('#roomScreen').is_visible() and typed.locator('#leaveRoomBtn').evaluate('e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1'), 'Created room controls fit a 320x568 phone')
    typed.screenshot(path=str(out / 'created-room-320x568.png'))
    manual_guest = load(name='MANUAL GUEST', size=layouts[3])
    manual_guest.locator('[data-mode=online]').click()
    manual_guest.locator('#joinCode').fill(typed_code)
    manual_guest.locator('#joinRoomBtn').click(); connected(manual_guest)
    own_name(manual_guest, 'MANUAL GUEST')
    check(state(manual_guest)['online']['code'] == typed_code and 'HOST' not in manual_guest.locator('#roomCallsignForm label').inner_text(), 'Join button joins an existing named room without taking host')

    stale_code = fresh_code()
    stale_missing = {'code': stale_code, 'token': 'old-missing-credential', 'name': 'RETURNING HOST', 'at': int(time.time()*1000)}
    restored = load('?room=' + stale_code, session=stale_missing, size=layouts[1]); connected(restored)
    own_name(restored, 'RETURNING HOST')
    sent = restored.evaluate('__sent.filter(m=>m.type==="join")')
    check(len(sent) == 2 and sent[0].get('token') == stale_missing['token'] and 'token' not in sent[1], 'Invite to deleted room retries once as a fresh join after stale resume')
    check(state(restored)['online']['code'] == stale_code and 'HOST' in restored.locator('#roomCallsignForm label').inner_text(), 'Stale-session invite creates missing room and makes visitor host')
    check(restored.evaluate('JSON.parse(sessionStorage.getItem("leqra.session")).token') != stale_missing['token'], 'Recreated room allocates fresh credentials instead of reusing expired identity')

    lost_code = fresh_code()
    lost_session = {'code': lost_code, 'token': 'background-reconnect-only', 'name': 'LOST PILOT', 'at': int(time.time()*1000)}
    lost = load(session=lost_session)
    lost.wait_for_function('document.getElementById("netStatus").classList.contains("error")')
    check(not state(lost)['online']['connected'] and lost.evaluate('__sent.filter(m=>m.type==="join").length') == 1, 'Background resume alone does not resurrect a missing room or start a join loop')
    lost.locator('#joinCode').fill(lost_code); lost.locator('#joinRoomBtn').click(); connected(lost)
    own_name(lost, 'LOST PILOT')
    check('HOST' in lost.locator('#roomCallsignForm label').inner_text(), 'Explicit Join after a failed background resume creates the requested room')

    storage_code = fresh_code()
    no_storage_host = load('?room=' + storage_code, blocked_storage=True, size=layouts[1]); connected(no_storage_host)
    own_name(no_storage_host, 'PILOT')
    check(state(no_storage_host)['online']['code'] == storage_code and 'HOST' in no_storage_host.locator('#roomCallsignForm label').inner_text(), 'Missing-room invitation creates a host even with browser storage blocked')
    invalid = load('?room=bad%00name')
    check(invalid.locator('#onlineScreen').is_visible() and invalid.evaluate('__sockets.length') == 0, 'Malformed invite opens error screen without contacting server')
    check('1–128' in invalid.locator('#netStatus').inner_text(), 'Malformed invite explains how to recover')
    # Storage restrictions should not block direct room entry.
    host3, code3 = create('STORAGE HOST')
    blocked = load('?room=' + code3, blocked_storage=True, size=layouts[1]); connected(blocked)
    check('PILOT' in names(blocked), 'Invite works when browser storage is unavailable')
    rename(blocked, 'NO STORAGE'); own_name(blocked, 'NO STORAGE')
    check('NO STORAGE' in names(blocked), 'Renaming still works with storage disabled')
    landing = load(name='RETURNING')
    check(state(landing)['phase'] == 'menu' and state(landing)['mode'] == 'solo' and landing.evaluate('__sockets.length') == 0, 'Ordinary link does not auto-join or auto-create a room')

    check(not errors, 'No JavaScript runtime errors in room feature flows')
    result = {'checks_passed': len(checks), 'checks': checks, 'javascript_errors': errors,
              'browser_version': browser.version, 'isolated_assets': args.isolated,
              'layouts': layouts, 'version': landing.evaluate('leqra.version')}
    (out / 'room-features-results.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    for context in contexts: context.close()
    browser.close()

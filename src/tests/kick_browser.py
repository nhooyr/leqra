"""Host-kick browser checks. Optional Playwright; see TESTING.md.
--isolated loads the exact shipped assets with synthetic URL/storage into
about:blank and uses real WebSockets to TestBrowserFixture. No production
origin policy is weakened. Screenshots and JSON are written to --output.
"""
import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('url', nargs='?', default='http://localhost:8080')
parser.add_argument('--isolated', action='store_true')
parser.add_argument('--browser', default=None)
parser.add_argument('--output', default='test-output/kick')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'web'
out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
checks, errors = [], []

def check(ok, label):
    assert ok, label
    checks.append(label)
    print('PASS', label, flush=True)

def state(page):
    return page.evaluate('leqra.getState()')

def wait_connected(page):
    page.wait_for_function('leqra.getState().online?.connected', timeout=10000)

def wait_count(page, count):
    page.wait_for_function('n=>leqra.getState().online?.players.length===n', arg=count)

def member(page, name):
    return next(p for p in state(page)['online']['players'] if p['name'] == name)

def removed(page):
    page.wait_for_function('!leqra.getState().online?.connected && document.querySelector("#netStatus").textContent.includes("removed")')

def session(page):
    return page.evaluate('JSON.parse(sessionStorage.getItem("leqra.session"))')

with sync_playwright() as pw:
    opts = {'headless': True}
    if args.browser: opts['executable_path'] = args.browser
    browser = pw.chromium.launch(**opts)
    contexts = []
    def load(name='PILOT', code='', size=(1365,950), tab=None):
        mobile = size[0]<760 or size[1]<620
        context = browser.new_context(viewport={'width':size[0], 'height':size[1]},
                                      is_mobile=mobile, has_touch=mobile)
        contexts.append(context)
        page = context.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        url = args.url.rstrip('/') + '/?test=1' + ('&room='+code if code else '')
        setup = r'''window.__sockets=[];window.__sent=[];window.__messages=[];window.__dropKickOnce=false;
const RealSocket=window.WebSocket;
window.WebSocket=class extends RealSocket{
 constructor(...a){super(...a);window.__sockets.push(this);this.addEventListener('message',e=>{
  let m;try{m=JSON.parse(e.data)}catch(_){return}window.__messages.push(m);
  if(window.__dropKickOnce && m.type==='kicked'){window.__dropKickOnce=false;e.stopImmediatePropagation();this.close(4000,'Test lost kick notification')}
 })}
 send(data){window.__sent.push(JSON.parse(data));return super.send(data)}
};'''
        if args.isolated:
            setup += r'''function memoryStorage(data){return {
 getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k],clear:()=>{for(const k in data)delete data[k]}
};}'''
            setup += f"Object.defineProperty(window,'localStorage',{{configurable:true,value:memoryStorage({json.dumps({'leqra.name':name})})}});"
            setup += f"Object.defineProperty(window,'sessionStorage',{{configurable:true,value:memoryStorage({json.dumps(tab or {})})}});"
            html = re.sub(r'<link[^>]*>', '', root.joinpath('index.html').read_text())
            for f in ['netcode.js','game.js']: html = html.replace(f'<script src="{f}" defer></script>', '')
            html = html.replace('</head>', '<style>'+root.joinpath('style.css').read_text()+'</style></head>')
            page.set_content(html)
            page.evaluate('()=>{'+setup+'}')
            js = root.joinpath('game.js').read_text().replace('(() => {','((location) => {',1)
            pos = js.rfind('})();'); js=js[:pos]+f'}})(new URL({json.dumps(url)}));'+js[pos+5:]
            page.add_script_tag(content=root.joinpath('netcode.js').read_text())
            page.add_script_tag(content=js)
        else:
            setup += f"localStorage.setItem('leqra.name',{json.dumps(name)});"
            for k,v in (tab or {}).items(): setup += f"sessionStorage.setItem({json.dumps(k)},{json.dumps(v)});"
            page.add_init_script(setup); page.goto(url)
        page.wait_for_function('window.leqra')
        if code and not (tab or {}).get('leqra.kicked'): wait_connected(page)
        return page
    def create(name='HOST', size=(1365,950)):
        page=load(name,size=size);page.locator('[data-mode=online]').click();page.locator('#createRoomBtn').click();wait_connected(page)
        return page,state(page)['online']['code']
    def kick(page, p, prefix='room', confirm=True):
        roster = '#roomRoster' if prefix=='room' else '#menuKickRoster'
        page.locator(f'{roster} [data-kick-target="{p["id"]}"]').click()
        page.wait_for_function('document.querySelector("#kickDialog").open')
        if confirm: page.locator('#confirmKickBtn').click()
    def close_pages(pages):
        for p in pages: p.context.close()

    host,code = create()
    alpha=load('ALPHA',code); beta=load('BETA',code,size=(390,844)); gamma=load('GAMMA',code)
    wait_count(host,4)
    check(host.locator('#roomRoster .kick-button').count()==3,'Host sees one Kick control for each other pilot')
    check(alpha.locator('.kick-button').count()==0 and beta.locator('.kick-button').count()==0,'Guests have no Kick controls')
    check(host.locator('#roomRoster [data-kick-target="0"]').count()==0,'Host has no self-kick control')
    a=member(host,'ALPHA');a_session=session(alpha)
    kick(host,a,confirm=False)
    check('ALPHA' in host.locator('#kickDescription').inner_text(),'Confirmation identifies the selected pilot')
    check(host.evaluate('document.activeElement.id')=='cancelKickBtn','Confirmation defaults keyboard focus to Cancel')
    host.keyboard.press('Escape')
    check(not host.locator('#kickDialog').evaluate('e=>e.open'),'Escape dismisses confirmation without toggling game menu')
    check(host.evaluate('__sent.filter(m=>m.type==="kick").length')==0,'Cancelling sends no kick request')
    kick(host,a,confirm=False)
    alpha.locator('#roomCallsign').fill('ALPHA NEW');alpha.locator('#roomCallsignForm button').click()
    host.wait_for_function('document.querySelector("#kickDescription").textContent.includes("ALPHA NEW")')
    check(member(host,'ALPHA NEW')['member']==a['member'],'Rename preserves selected seat and updates confirmation name')
    host.locator('#cancelKickBtn').click()
    host.locator('#readyBtn').click();beta.locator('#readyBtn').click()
    kick(host,member(host,'ALPHA NEW'));removed(alpha);wait_count(host,3)
    check(state(alpha)['phase']=='menu' and alpha.locator('#onlineScreen').is_visible(),'Kicked pilot returns to online menu with removal message')
    check(session(alpha) is None,'Kicked pilot reconnect credential is cleared')
    count=alpha.evaluate('__sockets.length')
    alpha.evaluate("window.dispatchEvent(new Event('online'));window.dispatchEvent(new Event('pagehide'))")
    alpha.wait_for_timeout(1100)
    check(alpha.evaluate('__sockets.length')==count and session(alpha) is None,'Kick stops automatic reconnect, online-event retries, and session rewrites')
    check(member(host,'HOST')['ready'] and member(host,'BETA')['ready'],'Other pilots keep their ready status')
    refresh=load('ALPHA NEW',code,tab={'leqra.kicked':code})
    check(refresh.evaluate('__sockets.length')==0 and 'removed' in refresh.locator('#netStatus').inner_text(),'Stale invite refresh cannot auto-join a kicked tab')
    refresh.context.close()
    alpha.locator('#joinRoomBtn').click();wait_connected(alpha);wait_count(host,4)
    new_a=member(host,'ALPHA NEW')
    check(new_a['member']!=a['member'] and session(alpha)['token']!=a_session['token'],'Manual rejoin gets a fresh identity; kick is not a permanent ban')
    # Forge a command from a guest. The UI is not the authority boundary.
    beta.evaluate('p=>__sockets.at(-1).send(JSON.stringify({type:"kick",target:p.id,member:p.member}))',new_a)
    beta.wait_for_function('__messages.some(m=>m.type==="error" && m.action==="kick" && m.code==="not_host")')
    check(len(state(host)['online']['players'])==4,'Server rejects forged guest kick without removing anyone')
    # Simulate transport loss of the terminal message. Reconnect must receive
    # "kicked", never resume_expired -> automatic invite fallback -> new seat.
    beta.evaluate('window.__dropKickOnce=true')
    kick(host,member(host,'BETA'));removed(beta);wait_count(host,3)
    check(beta.evaluate('__sockets.length')==2,'Dropped removal notice is recovered on one reconnect attempt')
    check(beta.evaluate('__sent.filter(m=>m.type==="join"&&!m.token).length')==1,'Revoked resume does not trigger invite-as-new-pilot fallback')
    kick(host,member(host,'GAMMA'),confirm=False)
    gamma.locator('#leaveRoomBtn').click();wait_count(host,2)
    check(not host.locator('#kickDialog').evaluate('e=>e.open'),'Confirmation closes when target leaves before approval')
    check(state(alpha)['online']['connected'],'Stale target disappearance does not remove a different pilot')
    host.screenshot(path=str(out/'desktop-host-room.png'))
    close_pages([host,alpha,beta,gamma])

    # Host on mobile: full lobby, native modal, in-match controls, then host handoff.
    host,code=create('MOBILE HOST',size=(390,844))
    guests=[load(n,code) for n in ['ONE','TWO','THREE']]
    wait_count(host,4)
    for w,h in [(390,844),(320,568),(844,390)]:
        host.set_viewport_size({'width':w,'height':h});host.wait_for_timeout(180)
        check(host.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'No horizontal overflow in host room {w}x{h}')
        host.locator('#roomRoster .kick-button').first.scroll_into_view_if_needed()
        check(host.locator('#roomRoster .kick-button').first.bounding_box()['height']>=40,f'Touch kick control is at least 40px tall {w}x{h}')
        area=host.locator('#arenaWrap').bounding_box();start=host.locator('#startRoomBtn').bounding_box()
        check(start['y']+start['height']<=area['y']+area['height'] and start['y']>=area['y'],f'Host Start button fits unobscured within arena {w}x{h}')
        host.screenshot(path=str(out/f'host-room-{w}x{h}.png'))
        kick(host,member(host,'ONE'),confirm=False)
        box=host.locator('#kickDialog').bounding_box()
        check(box['x']>=0 and box['y']>=0 and box['x']+box['width']<=w and box['y']+box['height']<=h,f'Confirmation fits mobile viewport {w}x{h}')
        host.screenshot(path=str(out/f'kick-confirm-{w}x{h}.png'))
        host.locator('#cancelKickBtn').tap()
    host.set_viewport_size({'width':390,'height':844});host.wait_for_timeout(180)
    for page in [host]+guests:page.locator('#readyBtn').click()
    host.locator('#startRoomBtn').click()
    for page in [host]+guests:page.wait_for_function('leqra.getState().phase==="playing"')
    host.locator('#pauseBtn').tap();guests[1].locator('#pauseBtn').click()
    check(host.locator('#hostControls').is_visible() and host.locator('#menuKickRoster .kick-button').count()==3,'Host can manage players from the live match menu')
    check(not guests[1].locator('#hostControls').is_visible(),'Guest match menu hides host controls')
    for w,h in [(390,844),(320,568),(844,390)]:
        host.set_viewport_size({'width':w,'height':h});host.wait_for_timeout(180)
        check(host.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'No horizontal overflow in match menu {w}x{h}')
        area=host.locator('#arenaWrap').bounding_box();leave=host.locator('#onlineLeaveBtn').bounding_box()
        check(leave['y']+leave['height']<=area['y']+area['height'] and leave['y']>=area['y'],f'Match menu actions fit unobscured within arena {w}x{h}')
        host.screenshot(path=str(out/f'host-match-menu-{w}x{h}.png'))
    one=member(host,'ONE');kick(host,one,prefix='menu',confirm=False)
    tick=state(host)['online']['serverTick'];host.wait_for_timeout(200)
    check(state(host)['online']['serverTick']>tick,'Kick confirmation does not block the shared simulation')
    host.locator('#confirmKickBtn').tap();removed(guests[0]);wait_count(host,3)
    host.wait_for_function('id=>leqra.getState().tanks.some(t=>t.id===id&&!t.alive)',arg=one['id'])
    check(state(host)['phase']=='playing','Remaining multiplayer match continues after a kick')
    host.locator('#onlineReturnBtn').tap()
    before=next(t['angle'] for t in state(host)['tanks'] if t['id']==0)
    host.keyboard.down('KeyD');host.wait_for_timeout(220);host.keyboard.up('KeyD')
    after=next(t['angle'] for t in state(host)['tanks'] if t['id']==0)
    check(abs(before-after)>.1,'Tank control still responds after closing host menu')
    host.locator('#pauseBtn').tap();host.locator('#onlineLeaveBtn').tap();wait_count(guests[1],2)
    guests[1].wait_for_function('!document.querySelector("#hostControls").hidden')
    check(guests[1].locator('#menuKickRoster .kick-button').count()==1,'Host handoff grants the new host Kick controls')
    kick(guests[1],member(guests[1],'THREE'),prefix='menu');removed(guests[2]);wait_count(guests[1],1)
    check(guests[2].locator('#netStatus').inner_text().startswith('You were removed'),'New host can remove the remaining opponent')
    guests[1].wait_for_function('leqra.getState().phase==="onlineLobby"',timeout=6000)
    check(not guests[1].locator('#startRoomBtn').is_enabled(),'Last-opponent kick ends the round and leaves a one-player lobby')
    check(not errors,'No JavaScript runtime errors in kick flows')
    report={'checks_passed':len(checks),'checks':checks,'javascript_errors':errors,'isolated_assets':args.isolated,'browser_version':browser.version,'version':root.joinpath('game.js').read_text().split("version:'")[-1].split("'")[0]}
    (out/'kick-results.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)
    browser.close()

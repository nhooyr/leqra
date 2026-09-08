"""v4.23 PWA/offline-networking, room UX and shutdown client regressions.

Run the opt-in Go fixture in another terminal first, for example:
  LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 \
    go test -run '^TestBrowserFixture$' -timeout 30m
Then run this script. The browser stays on about:blank and injects the exact shipped
assets because this build environment may block navigation to loopback URLs; gameplay
WebSockets still use the real loopback Go fixture.
"""
import argparse
import json
import re
import urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--server', default='http://127.0.0.1:18790')
parser.add_argument('--output', default='tests/results/v4.23-polish')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
web = root / 'web'
out = (root / args.output) if not Path(args.output).is_absolute() else Path(args.output)
out.mkdir(parents=True, exist_ok=True)

html = re.sub(r'<link[^>]*>', '', (web / 'index.html').read_text())
html = re.sub(r'<script[^>]*src="[^"]+"[^>]*></script>', '', html)
html = html.replace('</head>', '<style>' + (web / 'theme.css').read_text() + (web / 'style.css').read_text() + '</style></head>')
js = (web / 'game.js').read_text().replace('(() => {', '((location,history) => {', 1)
i = js.rfind('})();')
js = js[:i] + '})(window.__location,window.__history);' + js[i + 5:]
checks, errors = [], []

def check(ok, label):
    assert ok, label
    checks.append(label)
    print('PASS', label, flush=True)

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True, executable_path='/usr/bin/chromium')
    context = browser.new_context(viewport={'width': 1200, 'height': 900})
    page = context.new_page()
    sockets = []
    page.on('pageerror', lambda exc: errors.append(str(exc)))
    page.on('websocket', lambda ws: sockets.append(ws.url))
    page.on('dialog', lambda dialog: dialog.accept())
    page.set_content(html)
    page.evaluate('''server => {
      window.__location = new URL(server + '/?test=1');
      window.__history = {state:null, replaceState(state,title,url){this.state=state;window.__updatedURL=String(url)}};
      const data={'leqra.muted':'1'};
      const store=obj=>({getItem:k=>Object.hasOwn(obj,k)?obj[k]:null,setItem:(k,v)=>obj[k]=String(v),removeItem:k=>delete obj[k]});
      Object.defineProperty(window,'localStorage',{value:store(data)});
      Object.defineProperty(window,'sessionStorage',{value:store({})});
    }''', args.server)
    page.add_script_tag(content=(web / 'theme.js').read_text())
    page.add_script_tag(content=(web / 'netcode.js').read_text())
    page.add_script_tag(content=js)
    page.wait_for_function("window.__test && leqra.version === '4.34.0'")
    page.wait_for_timeout(100)

    check(len(sockets) == 0, 'Local startup opens no WebSocket')
    check(page.locator('#leaveRoomBtn').is_hidden(), 'Local room has no New local room action')

    # A stale server hello must stop online setup and give a reload instruction before
    # any room command can be sent. Use a tiny in-page socket here so the real fixture
    # remains available for the subsequent end-to-end checks.
    page.evaluate('''() => {
      window.__NativeWebSocket423 = window.WebSocket;
      class StaleSocket {
        static OPEN = 1;
        constructor(){
          this.readyState=0;this.bufferedAmount=0;
          setTimeout(()=>{this.readyState=1;this.onopen?.();this.onmessage?.({data:JSON.stringify({type:'server_hello',version:'4.22.0',protocol:1})});},0);
        }
        send(){}
        close(){this.readyState=3;setTimeout(()=>this.onclose?.(),0)}
      }
      window.WebSocket=StaleSocket;
      __test.shareLocalRoom();
    }''')
    page.wait_for_function("leqra.getState().mode === 'room' && document.querySelector('#roomStatus').textContent.includes('Reload the page')")
    check('Reload the page' in page.locator('#roomStatus').inner_text(), 'Version mismatch asks the player to reload before online play')
    check(page.evaluate("!__test.online.connected && __test.online.code === ''"), 'Version mismatch aborts online room setup')
    page.evaluate('window.WebSocket=window.__NativeWebSocket423;delete window.__NativeWebSocket423')

    teams = page.evaluate("""() => {
      __test.createLocalRoom();
      __test.setLocalRules({...__test.currentRules(),teamMode:'ffa'});
      __test.setLocalRules({...__test.currentRules(),teamMode:'teams'});
      return leqra.getState().room.players.map(p=>p.team);
    }""")
    check(teams == [1, 2, 3, 4], 'Teams activation distributes four tanks across all four teams')

    page.evaluate("__test.setLocalRules({...__test.currentRules(),teamMode:'ffa'});__test.shareLocalRoom()")
    page.wait_for_function("leqra.getState().online?.connected === true", timeout=10000)
    page.wait_for_function("leqra.getState().phase === 'onlineLobby'", timeout=10000)
    check(len(sockets) == 1, 'Explicit Share Room Online opens exactly one WebSocket')
    check(page.evaluate('__test.online.serverVersion') == '4.34.0', 'Online connection completes the v4.23 version handshake')

    before = page.evaluate('JSON.stringify(__test.walls)')
    page.evaluate('__test.unshareOnlineRoom()')
    page.wait_for_function("leqra.getState().mode === 'room'", timeout=10000)
    after = page.evaluate('JSON.stringify(__test.walls)')
    check(before == after, 'Unsharing preserves the displayed maze')

    page.evaluate('__test.shareLocalRoom()')
    page.wait_for_function("leqra.getState().online?.connected === true", timeout=10000)
    page.wait_for_function("leqra.getState().phase === 'onlineLobby'", timeout=10000)
    page.locator('#startRoomBtn').click()
    page.wait_for_function("leqra.getState().phase === 'playing'", timeout=10000)

    page.evaluate('__test.openChat()')
    check(page.evaluate('__test.roomChat.open && __test.chatHasFocus()'), 'Focused chat suppresses gameplay controls')
    page.locator('#arena').focus()
    page.keyboard.down('w')
    page.wait_for_timeout(60)
    state = page.evaluate('({open:__test.roomChat.open,focus:__test.chatHasFocus(),forward:__test.onlineControls().forward})')
    check(state['open'] and not state['focus'] and state['forward'], 'Visible but unfocused chat allows maze input')
    page.locator('#chatInput').focus()
    check(not page.evaluate('__test.onlineControls().forward'), 'Refocusing chat suppresses maze input again')
    page.keyboard.up('w')
    page.evaluate('__test.closeChat()')

    page.locator('#roomBtn').click()
    page.wait_for_function("!document.querySelector('#onlineMenuScreen').hidden")
    check(page.locator('#leaveMatchBtn').is_visible() and page.locator('#leaveMatchBtn').inner_text().strip() == 'Leave match', 'Online pause menu includes Leave match')
    # Regression: online-only pause actions must not leak into a later local room.
    page.evaluate('window.confirm=()=>true')
    page.locator('#leaveMatchBtn').click()
    page.wait_for_function("leqra.getState().mode === 'room'", timeout=10000)
    check(page.locator('#leaveMatchBtn').is_hidden(), 'Leave match is reset hidden after switching from online to local play')
    page.evaluate('__test.showVictory(-1, [])')
    check(page.locator('#victoryAgainBtn').evaluate("e=>getComputedStyle(e).backgroundColor") == 'rgb(57, 255, 136)', 'Local PLAY AGAIN uses the same neon green treatment as REMATCH')
    page.evaluate('__test.closeVictory()')

    page.evaluate('__test.shareLocalRoom()')
    page.wait_for_function("leqra.getState().online?.connected === true", timeout=10000)
    request = urllib.request.Request(args.server + '/_fixture/shutdown423', data=b'', method='POST')
    with urllib.request.urlopen(request, timeout=5) as response:
        check(response.status == 204, 'Shutdown fixture queued the server notice')
    page.wait_for_function("leqra.getState().mode === 'room'", timeout=10000)
    check('shutting down' in page.locator('#roomStatus').inner_text().lower(), 'Server shutdown returns the online client Home with a visible notice')
    check(page.locator('#shutdownDialog').is_visible() and 'SERVER SHUTTING DOWN' in page.locator('#shutdownDialog').inner_text(), 'Server shutdown opens a pronounced blocking notice')
    check(not errors, 'No uncaught browser errors: ' + str(errors))

    page.screenshot(path=str(out / 'v4.23-ui.png'))
    context.close()
    browser.close()

report = {'version': '4.34.0', 'passed': len(checks), 'checks': checks, 'errors': errors}
(out / 'results.json').write_text(json.dumps(report, indent=2))
print('TOTAL', len(checks))

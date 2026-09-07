"""Appearance and gameplay regression using real Chromium media emulation.
Navigation is restricted in this environment, so exact assets and storage/URL
adapters are injected. Online checks use the opt-in loopback Go test fixture.
Run: python tests/theme43_browser.py --url http://127.0.0.1:8431 --output test-output/theme43
"""
import argparse,json,re,secrets
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8431');ap.add_argument('--output',default='test-output/theme43');a=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text())
html=html.replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[];pages=[];contexts=[]
def wait(p,expression,**kwargs):return p.wait_for_function(expression,polling=50,**kwargs)
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
def load(b,size=(1365,950),scheme='dark',stored=None,blocked=False,live=False,code=None,watch=False):
 w,h=size;mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},color_scheme=scheme,device_scale_factor=2 if mobile else 1,has_touch=mobile,is_mobile=mobile);contexts.append(c)
 p=c.new_page();pages.append(p);p.set_default_timeout(9000);p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 query={'test':'1'}
 if code:query['room']=code
 if watch:query['spectate']='1'
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};window.__store=a.stored;window.__sent=[];
 const store=d=>({getItem:k=>{if(a.blocked)throw Error('denied');return d[k]??null;},setItem:(k,v)=>{if(a.blocked)throw Error('denied');d[k]=String(v);},removeItem:k=>{if(a.blocked)throw Error('denied');delete d[k];}});
 Object.defineProperty(window,'localStorage',{value:store(__store)});Object.defineProperty(window,'sessionStorage',{value:store({})});
 if(!a.live)window.requestAnimationFrame=()=>0;
 const WS=WebSocket;window.WebSocket=class extends WS{send(v){__sent.push(JSON.parse(v));return super.send(v)}};
 }''',dict(url=a.url+'/?'+urlencode(query),stored=stored if stored is not None else {'leqra.name':'PILOT','leqra.muted':'1'},blocked=blocked,live=live))
 for name in ['theme.js','netcode.js']:p.add_script_tag(content=(web/name).read_text())
 p.add_script_tag(content=js);wait(p, 'window.__test && leqra.version==="4.3.0"');p.evaluate('__test.render()');return p,c

def shape(p):return p.evaluate('''()=>{const e=document.querySelector('#arenaWrap'),r=e.getBoundingClientRect(),c=document.querySelector('#arena');return [r.x,r.y,r.width,r.height,c.width,c.height];}''')
def skin(p):return p.evaluate('leqra.getState().appearance')
def physical(p):return p.evaluate('JSON.stringify({state:leqra.getState(),walls:__test.walls,pickups:__test.pickups})')
def normal_state(p):
 return p.evaluate('''()=>{const s=leqra.getState();delete s.appearance;return JSON.stringify({s,walls:__test.walls,pickups:__test.pickups,bullets:__test.bullets});}''')
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  for scheme in ['dark','light']:
   p,c=load(b,scheme=scheme)
   check(skin(p)=={'preference':'auto','resolved':scheme},f'{scheme}: clean profile follows browser')
   colors=p.evaluate('''()=>{const r=getComputedStyle(document.documentElement),button=getComputedStyle(document.querySelector('#startRoomBtn'));return {accent:r.getPropertyValue('--accent').trim(),scheme:r.colorScheme,background:button.backgroundColor,text:button.color,meta:document.querySelector('meta[name="theme-color"]').content};}''')
   check(colors['accent']==('#39ff14' if scheme=='dark' else '#a100ff'),f'{scheme}: exact requested neon accent')
   check(colors['scheme']==scheme,f'{scheme}: native inputs use matching color-scheme')
   check(colors['meta']==('#111619' if scheme=='dark' else '#f5f2fa'),f'{scheme}: browser theme-color follows appearance')
   p.locator('#roomControlsBtn').click()
   check(p.locator('#themeMode').input_value()=='auto',f'{scheme}: settings default to Auto')
   check(p.locator('#themeMode option').count()==3,f'{scheme}: exactly Auto / Dark / Light choices')
   p.locator('#themeMode').select_option('light' if scheme=='dark' else 'dark')
   expected='light' if scheme=='dark' else 'dark'
   check(skin(p)['resolved']==expected,f'{scheme}: manual UI selection takes effect immediately')
   p.emulate_media(color_scheme=scheme)
   check(skin(p)['resolved']==expected,f'{scheme}: explicit choice ignores system')
   stored=p.evaluate('__store');q,qc=load(b,scheme=scheme,stored=stored)
   check(skin(q)['resolved']==expected and skin(q)['preference']==expected,f'{scheme}: manual selection survives a fresh page load')
   qc.close();p.locator('#themeMode').select_option('auto');p.emulate_media(color_scheme=expected);wait(p, '(s)=>leqraTheme.resolved===s',arg=expected)
   check(skin(p)['preference']=='auto',f'{scheme}: Auto resumes live preference tracking')
   p.locator('[data-close-dialog="controlsDialog"]').click();p.locator('#joinOtherBtn').click()
   check(p.evaluate('getComputedStyle(document.querySelector("#joinRoomBtn")).backgroundColor===getComputedStyle(document.querySelector("#createRoomBtn")).backgroundColor'),f'{scheme}: Join and Create still match')
   c.close()
  # Storage denial is explicitly reported, with functioning session appearance.
  p,c=load(b,scheme='light',blocked=True);p.locator('#roomControlsBtn').click();p.locator('#themeMode').select_option('dark')
  check(skin(p)['resolved']=='dark' and 'Session only' in p.locator('#themeStatus').inner_text(),'Blocked storage: manual choice works and save limitation is shown');c.close()
  p,c=load(b,scheme='light',stored={'leqra.theme.v1':'invalid','leqra.feedback.v1':'{"audio":false,"fps":true}','leqra.muted':'1'})
  check(skin(p)['preference']=='auto','Invalid saved theme falls back to Auto')
  check(p.evaluate('JSON.parse(__store["leqra.feedback.v1"]).audio===false'),'Theme startup preserves prior audio preferences');c.close()
  # Every viewport, every appearance: no layout changes or simulation edits.
  for size in [(1365,950),(390,844),(320,568),(844,390)]:
   p,c=load(b,size=size);p.locator('#addLocalBtn').click();p.locator('#startRoomBtn').click();p.evaluate("__test.setPhase('playing');__test.tanks.forEach(t=>t.human=true);__test.updateHUD(true)")
   state=normal_state(p);box=shape(p)
   for scheme in ['light','dark']:
    p.evaluate('(s)=>{leqraTheme.setPreference(s);__test.render();}',scheme)
    check(normal_state(p)==state,f'{size} {scheme}: maze, tanks, shots, scores and rules unchanged')
    check(shape(p)==box,f'{size} {scheme}: canvas and HUD geometry unchanged')
    check(p.evaluate('document.body.scrollWidth<=innerWidth+1'),f'{size} {scheme}: no horizontal overflow')
    check(p.evaluate('''()=>{__test.renderPowerLegend();return [...document.querySelectorAll('.power-list canvas')].every(e=>{const f=document.createElement('canvas');f.width=e.width;f.height=e.height;const c=f.getContext('2d');c.setTransform(f.width/26,0,0,f.height/26,f.width/2,f.height/2);__test.powerIcon(e.dataset.powerIcon,c);return f.toDataURL()===e.toDataURL();});}'''),f'{size} {scheme}: all ten legend/maze icons match')
    rgba=p.evaluate('Array.from(document.querySelector("#arena").getContext("2d").getImageData(1,1,1,1).data)')
    check(rgba[:3]==([229,222,238] if scheme=='light' else [16,24,30]),f'{size} {scheme}: canvas changes with the page')
    p.screenshot(path=str(out/f'playing-{scheme}-{size[0]}x{size[1]}.png'))
    for t in ['cannon','speed','shield','scope','ghost']:p.evaluate('(t)=>{for(const tank of __test.tanks.filter(t=>t.localIndex===1||t.id===0))__test.grantPower(tank,t);__test.updateHUD(true);__test.render()}',t)
    check(shape(p)==box,f'{size} {scheme}: stacked buffs still cannot resize arena')
    state=normal_state(p)
    p.evaluate('document.querySelector("#controlsDialog").showModal()');p.screenshot(path=str(out/f'appearance-{scheme}-{size[0]}x{size[1]}.png'))
    check(p.locator('#themeMode').evaluate('(e)=>e.scrollWidth<=e.clientWidth+1'),f'{size} {scheme}: theme selector fits')
    p.locator('[data-close-dialog="controlsDialog"]').click();state=normal_state(p)
   # System change during live play must preserve held controls, map and phase.
   p.evaluate("leqraTheme.setPreference('auto')");p.keyboard.down('w');before=normal_state(p);p.emulate_media(color_scheme='light');wait(p, 'leqraTheme.resolved==="light"')
   check(normal_state(p)==before,f'{size}: automatic switch does not reset live game')
   moved=p.evaluate('''()=>{const t=__test.tanks[0],old=[t.x,t.y];__test.humanControl(t,.05);return Math.hypot(t.x-old[0],t.y-old[1])>0;}''');p.keyboard.up('w')
   check(moved,f'{size}: held movement survives automatic change')
   p.evaluate('__test.finishMatch(0)');p.screenshot(path=str(out/f'victory-light-{size[0]}x{size[1]}.png'))
   check(p.locator('#victoryDialog').evaluate('(e)=>e.open') and p.locator('#victoryStats').is_visible(),f'{size}: themed congratulations and post-match stats remain visible')
   text=p.locator('#cooldownText1').inner_text();p.evaluate("leqraTheme.setPreference('dark');__test.updateHUD(true)")
   check(p.locator('#cooldownText1').inner_text()==text=='MATCH COMPLETE',f'{size}: theme switch cannot restart the completed cooldown')
   c.close()
  # Native browser media notifications, real server room/spectator/chat, no theme traffic.
  host,hc=load(b,live=True,scheme='dark',stored={'leqra.name':'HOST','leqra.muted':'1'})
  host.locator('#addLocalBtn').click();host.locator('#copyInviteBtn').click();wait(host, 'leqra.getState().online?.connected');code=host.evaluate('__test.online.code')
  viewer,vc=load(b,size=(320,568),scheme='light',live=True,code=code,watch=True,stored={'leqra.name':'VIEWER','leqra.muted':'1'})
  check(not viewer.evaluate('leqra.getState().online?.connected||false'),'Spectator link still asks for callsign before joining')
  viewer.locator('#joinRoomBtn').click();wait(viewer, 'leqra.getState().online?.spectating')
  check(skin(host)['resolved']=='dark' and skin(viewer)['resolved']=='light','Online player and spectator can use different themes in one room')
  host.locator('#startRoomBtn').click();wait(host, 'leqra.getState().phase==="playing"');wait(viewer, 'leqra.getState().phase==="playing"')
  host.evaluate('window.__socketBefore=__test.online.socket;window.__predictorBefore=__test.online.predictor;window.__generationBefore=__test.online.generation;window.__idBefore=__test.online.id;window.__sent=[]')
  host.keyboard.down('w');host.keyboard.down('ArrowUp');host.emulate_media(color_scheme='light');wait(host, 'leqraTheme.resolved==="light"');host.keyboard.up('w');host.keyboard.up('ArrowUp')
  check(host.evaluate('__test.online.socket===__socketBefore && __test.online.predictor===__predictorBefore && __test.online.generation===__generationBefore && __test.online.id===__idBefore'),'Live appearance change preserves socket, local predictor, arena generation and identity')
  check(host.evaluate('__sent.every(m=>["input","ping"].includes(m.type))'),'Appearance switch sends no room edits, restarts or extra matchmaking messages')
  check(viewer.evaluate('leqraTheme.preference==="auto" && leqraTheme.resolved==="light"'),'Host changing appearance cannot override spectator preference')
  host.locator('#chatBtn').click();host.locator('#chatInput').fill('Purple and green: same room!');host.locator('#chatSendBtn').click();viewer.locator('#chatBtn').click();wait(viewer, 'document.querySelector("#chatMessages").textContent.includes("Purple and green")')
  check(True,'Room chat works across light/dark clients and spectators')
  viewer.screenshot(path=str(out/'chat-light-320.png'));viewer.locator('#chatCloseBtn').click();viewer.screenshot(path=str(out/'online-spectator-light-320.png'))
  host.locator('#chatCloseBtn').click();host.evaluate('leqraTheme.setPreference("dark")');host.screenshot(path=str(out/'online-player-dark.png'))
  before=host.evaluate('__test.online.id');host.evaluate('__test.online.socket.close(4000,"theme regression")');wait(host, 'leqra.getState().online?.connected',timeout=15000)
  check(host.evaluate('__test.online.id')==before and skin(host)['resolved']=='dark','Reconnect retains identity and manual appearance')
  hc.close();vc.close();check(not errors,'No JavaScript errors across theme and live-room checks')
 finally:
  for p in pages:
   if not p.is_closed():
    try:p.screenshot(path=str(out/'failure.png'))
    except Exception:pass
  b.close();(out/'results.json').write_text(json.dumps({'version':'4.3.0','passed':len(checks),'checks':checks,'errors':errors},indent=2))
print('TOTAL',len(checks),flush=True)

"""v3.5 shipped assets + real loopback Go WebSockets; synthetic URL/storage adapters."""
import argparse,json,re,time,traceback
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:18790');ap.add_argument('--output',default='test-output/features35');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(v,label):
 if not v:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');contexts=[]
 def load(name='HOST',size=(1365,950),code=None,watch=False,storage=None):
  mobile=size[0]<760 or size[1]<620;c=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(c);p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code,**({'spectate':1} if watch else {})}) if code else '')
  p.evaluate(r'''([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({'leqra.name':name,'leqra.muted':'1'},storage||{});Object.defineProperty(window,'localStorage',{value:store(__store)});window.__session={};Object.defineProperty(window,'sessionStorage',{value:store(__session)});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{window.__copied=v}}});}''',[url,args.url.replace('http:','ws:')+'/ws',name,storage])
  js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:];p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def conn(p):p.wait_for_function('leqra.getState().online?.connected',timeout=12000)
 def start(p):p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=9000)
 def rules(p,**values):
  selected_mode=values.pop('mode',None)
  if selected_mode is not None:
   p.locator('[data-room-mode="'+selected_mode+'"]').click();p.wait_for_function('(mode)=>leqra.getState().rules.mode===mode',arg=selected_mode)
  for setting,selector in [('teamMode','#roomTeamMode'),('mapSize','#roomMapSize')]:
   value=values.pop(setting,None)
   if value is not None:
    control=p.locator(selector)
    if control.is_disabled():assert control.input_value()==str(value)
    else:control.select_option(str(value));p.wait_for_function('([key,value])=>leqra.getState().rules[key]===value',arg=[setting,value])
  p.locator('#roomRulesBtn').click()
  for k,v in values.items():
   e=p.locator('#rule-'+k)
   if k in ['mapSize','teamMode','pickupRate']:
    if e.is_disabled():assert e.input_value()==str(v)
    else:e.select_option(str(v))
   else:e.fill(str(v))
  p.locator('#applyRulesBtn').click();p.wait_for_function('!document.querySelector("#rulesDialog").open')
 def arena(p):return p.locator('#arenaWrap').bounding_box()
 def settings(p):p.locator('#roomControlsBtn').click()
 def closeControls(p):p.locator('[data-close-dialog="controlsDialog"]').click()
 def chat(p,text):
  if not p.locator('#chatPanel').is_visible():p.locator('#chatBtn').click()
  p.locator('#chatInput').fill(text);p.locator('#chatInput').press('Enter');p.wait_for_function('!document.querySelector("#chatSendBtn").disabled',timeout=4000)
 def message(p,text):p.wait_for_function('text=>[...document.querySelectorAll("#chatMessages p")].some(p=>p.textContent===text)',arg=text)
 def active(p):return len(state(p)['room']['players'])
 def snap(p,name):
  if name.startswith('chat-'):
   bounds=p.locator('#chatPanel').bounding_box();vp=p.viewport_size
   check(bounds['x']>=0 and bounds['x']+bounds['width']<=vp['width']+1 and bounds['y']+bounds['height']<=vp['height']+1,'Chat fits viewport '+name)
   check(p.locator('#pauseBtn').bounding_box()['x']+p.locator('#pauseBtn').bounding_box()['width']<=vp['width']+1,'Header actions fit '+name)
  p.screenshot(path=str(out/(name+'.png')))
 try:
  for size in [(1365,950),(320,568),(844,390)]:
   p=load(size=size);check(state(p)['rules']['mapSize']=='large','Default 12x10 '+str(size));check(p.locator('#chatBtn').is_hidden(),'Local room has no misleading online chat '+str(size));check(p.locator('#fpsIndicator').is_hidden(),'FPS opt-in '+str(size))
   while active(p)<7:p.locator('#addBotBtn').click()
   p.locator('#addLocalBtn').click();check(active(p)==8,'Eight mixed local seats '+str(size));check(p.locator('#addBotBtn').is_disabled(),'Ninth tank disabled '+str(size));check(p.locator('#seatCount').inner_text().endswith('/ 8'),'Room capacity label '+str(size))
   rules(p,mapSize='huge',mode='koth',teamMode='ffa',timeLimit=300,scoreTarget=300)
   settings(p);p.locator('#showFPS').check();p.locator('#performanceMode').check();closeControls(p);p.wait_for_timeout(900);check('FPS' in p.locator('#fpsIndicator').inner_text(),'FPS reading '+str(size));saved=p.evaluate('__store');check(json.loads(saved['leqra.feedback.v1'])['fps'],'FPS saved '+str(size));snap(p,'room-'+str(size[0]))
   start(p);check(len(state(p)['tanks'])==8 and state(p)['world']['cols']==14 and state(p)['world']['rows']==12,'Eight tanks on 14x12 '+str(size))
   p.evaluate('''()=>{__test.setPhase('paused');__test.clearBullets();for(const t of __test.tanks){t.alive=true;t.invulnerable=999;}__test.updateHUD(true);}''')
   dims=arena(p);p.evaluate('''()=>{for(const t of __test.tanks)if(t.human){__test.grantPower(t,'speed');t.shield=10;}__test.updateHUD(true);}''');p.wait_for_timeout(100);check(arena(p)==dims,'Buffs keep stable arena '+str(size));check(p.locator('#pilotLoadout2').is_visible(),'High-seat local player ammo '+str(size))
   # Fire through the normal remapped human controller for high-numbered P2.
   ok=p.evaluate('''()=>{const t=__test.tanks.find(t=>t.human&&t.id!==0);__test.clearInput();__test.clearBullets();t.cooldown=0;t.invulnerable=0;window.dispatchEvent(new KeyboardEvent('keydown',{code:'Space',bubbles:true}));__test.humanControl(t,1/120);window.dispatchEvent(new KeyboardEvent('keyup',{code:'Space',bubbles:true}));return __test.bullets.some(b=>b.owner===t.id);}''')
   # Paused input is intentionally ignored; resume momentarily for this input check.
   if not ok:
    ok=p.evaluate('''()=>{__test.setPhase('playing');const t=__test.tanks.find(t=>t.human&&t.id!==0);t.cooldown=0;window.dispatchEvent(new KeyboardEvent('keydown',{code:'Space',bubbles:true}));__test.humanControl(t,1/120);window.dispatchEvent(new KeyboardEvent('keyup',{code:'Space',bubbles:true}));__test.setPhase('paused');return __test.bullets.some(b=>b.owner===t.id);}''')
   check(ok,'Space fires secondary seat seven '+str(size));snap(p,'playing-'+str(size[0]));check(p.locator('#arena').evaluate('(e)=>e.width')<=size[0]+5,'Performance DPR cap '+str(size));p.close()
  p=load(storage=saved);check(p.locator('#fpsIndicator').is_visible(),'FPS choice restores on reload');settings(p);check(p.locator('#performanceMode').is_checked(),'Graphics preference restores');closeControls(p);p.close()
  # New source/range broad phase must match full wall iteration in the browser too.
  p=load();check(p.evaluate('''()=>{const full=__test.walls;let seed=35;const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const T=__test,world=leqra.getState().world;const original=T.rayWalls.toString();const brute=eval('('+original.replace('nearbyWalls(x,y,dx,dy,r)','full')+')');for(let i=0;i<2000;i++){let x=rnd()*world.width,y=rnd()*world.height,dx=(rnd()-.5)*world.width,dy=(rnd()-.5)*world.height,r=rnd()*20;if(i%2===0){dx*=.05;dy*=.05}const a=T.rayWalls(x,y,dx,dy,r),b=brute(x,y,dx,dy,r);if(JSON.stringify(a)!==JSON.stringify(b))return false;}return true}'''),'Indexed browser wall rays equal exhaustive reference')
  check(p.evaluate('''source=>{const walls=__test.walls,clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),brute=eval('('+source+')');let seed=351;const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const world=leqra.getState().world;for(let i=0;i<4000;i++){let a={x:rnd()*world.width,y:rnd()*world.height,r:9+rnd()*15};if(i%2===0){const w=walls[Math.floor(rnd()*walls.length)];a.x=w.x+w.w*rnd();a.y=w.y+w.h*rnd();}const b={...a};__test.resolveWalls(a);brute(b);if(Math.abs(a.x-b.x)>1e-8||Math.abs(a.y-b.y)>1e-8)return false;}return true}''',root.joinpath('tests/fixtures/resolve-wall-original35.js').read_text()),'Indexed browser tank resolution matches original at 4000 positions');p.close()
  # Publish seven tanks, admit an eighth human, then overflow + dedicated watchers.
  host=load();code='Eight & chat 💥 '+str(time.time_ns())
  while active(host)<7:host.locator('#addBotBtn').click()
  rules(host,mode='koth',timeLimit=600,scoreTarget=300)
  host.locator('#localRoomName').fill(code);host.locator('#copyInviteBtn').click();conn(host)
  guest=load('GUEST',code=code);conn(guest);guest.wait_for_function('leqra.getState().room.players.length===8');check(not state(guest)['online']['spectating'] and state(guest)['online']['id']==7,'Eighth online player gets final tank')
  viewer=load('OVERFLOW',size=(320,568),code=code);conn(viewer);check(state(viewer)['online']['spectating'],'Ninth normal join becomes spectator');watch=load('WATCHER',size=(844,390),code=code,watch=True);check(watch.locator('#pilotName').is_visible(),'Watch link still requires callsign');watch.locator('#pilotName').fill('WATCHER');watch.locator('#joinRoomBtn').click();conn(watch)
  for p in [host,guest,viewer,watch]:check(p.locator('#chatBtn').is_visible(),'Chat available to '+state(p)['room']['players'][0]['name']+' member '+str(state(p)['online']['id']))
  chat(host,'Hello everyone 💥');message(guest,'Hello everyone 💥');message(viewer,'Hello everyone 💥');check(viewer.locator('#chatBadge').inner_text()=='1','Unread count includes players for spectator')
  chat(viewer,'<img src=x onerror="window.injected=true">');message(host,'<img src=x onerror="window.injected=true">');check(not host.evaluate('window.injected||false') and host.locator('#chatMessages img').count()==0,'Untrusted chat stays literal text');check('WATCHING' in host.locator('#chatMessages').inner_text(),'Spectator role shown')
  chat(guest,'Tank eight ready');message(watch,'Tank eight ready');check('GUEST' in watch.locator('#chatMessages').inner_text(),'Player callsign attributed in chat')
  # Ready and start; chat continues without pausing or moving the arena.
  for p in [host,guest,viewer,watch]:
   if p.locator('#chatPanel').is_visible():p.locator('#chatCloseBtn').click()
  guest.locator('#readyBtn').click();host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');start(host);viewer.wait_for_function('leqra.getState().phase==="playing"');check(len(state(viewer)['tanks'])==8,'Spectator receives eight authoritative tanks');viewer.wait_for_timeout(700)
  before=arena(viewer);chat(viewer,'Watching the live match');message(guest,'Watching the live match');check(arena(viewer)==before,'Opening chat never resizes arena');check(state(viewer)['phase']=='playing','Chat does not pause online game');snap(viewer,'chat-320');watch.locator('#chatBtn').click();snap(watch,'chat-844');host.locator('#chatBtn').click();snap(host,'chat-desktop')
  # Keyboard gameplay is neutral throughout chat, even with P1-bound letters.
  n=host.evaluate('__sent.length');host.locator('#chatInput').fill('');host.locator('#chatInput').press('f');host.locator('#chatInput').press('w');host.wait_for_timeout(100);check(host.evaluate('n=>__sent.slice(n).filter(m=>m.type==="input").every(m=>!m.fire&&!m.forward)',n),'Typing chat never fires/moves a tank')
  host.locator('#chatInput').press('Escape');check(host.locator('#chatPanel').is_hidden(),'Escape closes chat without room menu')
  # Late viewer sees bounded history; reconnect produces neither duplicate messages nor tank promotion.
  late=load('LATE',code=code);conn(late);message(late,'Watching the live match');check(state(late)['online']['spectating'],'History subscriber remains spectator');count=late.locator('#chatMessages .chat-message').count();late.evaluate('__sockets.at(-1).close()');late.wait_for_function('__sockets.length>1&&leqra.getState().online.connected',timeout=15000);message(late,'Watching the live match');check(late.locator('#chatMessages .chat-message').count()==count,'Reconnect history has no duplicates')
  # A different room never receives messages from this room.
  elsewhere=load('ELSEWHERE');elsewhere.locator('#localRoomName').fill('Other '+str(time.time_ns()));elsewhere.locator('#copyInviteBtn').click();conn(elsewhere);chat(host,'Room-only message');message(guest,'Room-only message');elsewhere.wait_for_timeout(100);check(elsewhere.locator('#chatMessages .chat-message').count()==0,'Chat isolated to its room')
  host.locator('#chatCloseBtn').click();host.locator('#roomBtn').click();host.locator('#returnRoomBtn').click();host.wait_for_function('leqra.getState().phase==="onlineLobby"');guest.wait_for_function('leqra.getState().phase==="onlineLobby"');check(host.locator('#chatMessages .chat-message').count()>=5,'Returning to room keeps chat history');guest.locator('#readyBtn').click();host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');start(host);message(viewer,'Room-only message');check(state(viewer)['online']['spectating'],'New match keeps chatting spectator role')
  check(not errors,'No browser runtime errors')
  report={'version':'3.6.0','passed':len(checks),'checks':checks,'errors':errors,'limits':'Chromium desktop/mobile emulation, exact assets injected with synthetic URL/storage, real loopback Go server. No physical devices/public internet.'};(out/'report.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 except Exception:
  (out/'failure.json').write_text(json.dumps({'passed':checks,'errors':errors,'traceback':traceback.format_exc()},indent=2))
  for i,c in enumerate(contexts):
   for p in c.pages:
    try:p.screenshot(path=str(out/('failure-'+str(i)+'.png')))
    except:pass
  raise
 finally:browser.close()

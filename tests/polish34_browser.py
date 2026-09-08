"""v3.4: exact browser assets, local simulation and loopback Go snapshots.
Uses Location/History/storage adapters; no shipped production debug endpoint.
"""
import argparse,json,re,time,zipfile
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8878');ap.add_argument('--output',default='test-output/polish34');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--baseline');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[];measurements=[]
def check(v,label):
 if not v:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def fixture(code,action,player=0):
 with urlopen(Request(args.url+'/_fixture/features32',data=json.dumps(dict(code=code,action=action,player=player)).encode(),headers={'Content-Type':'application/json'}),timeout=5) as r:return json.load(r)
def state(p):return p.evaluate('leqra.getState()')
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[]
 def load(name='HOST',size=(1365,950),code=None,watch=False,storage=None,source=None):
  mobile=size[0]<760 or size[1]<620;context=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(context);p=context.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  w=source or web;html=re.sub(r'<link[^>]*>','',w.joinpath('index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+w.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code,**({'spectate':1} if watch else {})}) if code else '')
  p.evaluate(r'''([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied='';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({'leqra.name':name,'leqra.muted':'1'},storage||{});Object.defineProperty(window,'localStorage',{value:store(__store)});Object.defineProperty(window,'sessionStorage',{value:store({})});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{__copied=v}}});}''',[url,args.url.replace('http:','ws:')+'/ws',name,storage])
  js=w.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
  p.add_script_tag(content=w.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def closewin(p):
  if p.locator('#victoryDialog').count() and p.locator('#victoryDialog').is_visible():p.locator('#victoryCloseBtn').click()
 def preset(p,index):
  closewin(p);p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('builtin:'+str(index));p.locator('#loadPresetBtn').click();p.wait_for_function('!document.querySelector("#presetsDialog").open')
 def start(p):
  closewin(p);p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=9000)
 def room(p):
  closewin(p)
  if state(p)['mode']=='room':p.evaluate('__test.returnToRoom()');return
  p.locator('#roomBtn').click();p.locator('#returnRoomBtn').click();p.wait_for_function('["menu","onlineLobby"].includes(leqra.getState().phase)')
 def rules(p,**values):
  closewin(p)
  selected_mode=values.pop('mode',None)
  if selected_mode is not None:
   p.locator('[data-room-mode="'+selected_mode+'"]').click();p.wait_for_function('(mode)=>leqra.getState().rules.mode===mode',arg=selected_mode)
  p.locator('#roomRulesBtn').click()
  for k,v in values.items():
   n=p.locator('#rule-'+k)
   if k=='friendlyFire':n.set_checked(v)
   elif k in ['teamMode','mapSize','pickupRate']:
    if n.is_disabled():assert n.input_value()==str(v)
    else:n.select_option(str(v))
   else:n.fill(str(v))
  p.locator('#applyRulesBtn').click();p.wait_for_function('!document.querySelector("#rulesDialog").open')
 def box(p):return p.evaluate('''()=>{const r=document.querySelector('#arenaWrap').getBoundingClientRect(),u=document.querySelector('.underbar').getBoundingClientRect();return {width:r.width,height:r.height,x:r.x,y:r.y,hud:u.height,canvasW:document.querySelector('#arena').width,canvasH:document.querySelector('#arena').height};}''')
 def freeze(p):p.evaluate('''()=>{__test.setPhase('paused');__test.clearBullets();for(const t of __test.tanks){t.power=null;t.powerTime=0;t.speedTime=0;t.shield=0;t.alive=true;t.invulnerable=0;}__test.updateHUD(true);}''');p.wait_for_timeout(80)
 try:
  # Actual original-layout reproduction, optional original zip supplied by release runner.
  if args.baseline:
   target=out/'baseline';target.mkdir(exist_ok=True)
   with zipfile.ZipFile(args.baseline) as z:
    for name in z.namelist():
     if '/web/' in name:z.extract(name,target)
   oldweb=target/'leqra-online/web'
   p=load(size=(390,844),source=oldweb);start(p);freeze(p);before=box(p)
   p.evaluate("__test.grantPower(__test.tanks[0],'speed');__test.updateHUD(true)");p.wait_for_timeout(100);after=box(p)
   measurements.append({'baseline':'v3.3 buff HUD','before':before,'after':after});check(before['height']!=after['height'],'Reproduced v3.3 power-up-triggered arena resize')
   resurrect=p.evaluate('''()=>{const T=__test,o=T.online,now=performance.now();const s={generation:1,tick:100,phaseTime:0,roundClock:60,received:now+12,tanks:[],bullets:[],pickups:[],tankMap:new Map(),bulletMap:new Map()};o.buffer=new leqraNet.SnapshotBuffer();o.buffer.push(s,now);o.snapshots=o.buffer.items;o.trails=new Map();T.setPhase('playing');T.renderOnlineMotion(.016,now);T.updateHUD(true);return !document.querySelector('#announcer').hidden&&document.querySelector('#announceMain').textContent==='GO'}''')
   check(resurrect,'Reproduced v3.3 stale GO from RAF timestamp preceding snapshot receipt');p.close()
  # Reserve HUD geometry for both local pilots at multiple orientations and sizes.
  for size in [(1365,950),(390,844),(320,568),(844,390)]:
   for two in [False,True]:
    p=load(size=size)
    if two:p.locator('#addLocalBtn').click()
    start(p);freeze(p);base=box(p)
    for power in ['speed','shield','scatter','rapid','homing','laser','grenade']:
     p.evaluate("power=>{for(const t of __test.tanks){if(t.human)__test.grantPower(t,power)};__test.updateHUD(true);}",power);p.wait_for_timeout(45)
     current=box(p);check(current==base,f'{size} {1+two} pilots: {power} does not change arena/HUD geometry')
    p.evaluate("()=>{for(const t of __test.tanks){t.power=null;t.speedTime=0;t.shield=0;t.alive=false;}__test.updateHUD(true)}");p.wait_for_timeout(50);check(box(p)==base,f'{size} {1+two} pilots: expiry/death keeps arena stable')
    check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No horizontal page overflow '+str(size)+' '+str(two))
    p.screenshot(path=str(out/f'hud-{size[0]}x{size[1]}-{two}.png'));p.close()
  # Self damage on both teams, every slot, including local second seat and bots.
  p=load();preset(p,2);start(p);freeze(p)
  result=p.evaluate('''()=>{const T=__test;let result=[];for(const t of T.tanks){t.team=2;t.alive=true;t.shield=0;t.invulnerable=0;T.hurt(t,{owner:t.id});result.push(!t.alive);}return result}''');check(all(result),'All local tank slots die from their own shots with friendly fire off')
  room(p);rules(p,friendlyFire=True);check(state(p)['rules']['friendlyFire'] is True,'Host enables friendly fire in local rules')
  p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('Friendly fire test');p.locator('#savePresetBtn').click();check(json.loads(p.evaluate('__store["leqra.presets.v1"]'))['items'][0]['rules']['friendlyFire'],'Saved preset retains friendly-fire setting');p.locator('[data-close-dialog="presetsDialog"]').click();start(p);freeze(p)
  hit=p.evaluate('''()=>{const T=__test,[a,b]=T.tanks;for(const t of [a,b])Object.assign(t,{team:2,alive:true,shield:0,invulnerable:0});T.hurt(b,{owner:a.id});return !b.alive}''');check(hit,'Enabled friendly fire harms local teammate')
  room(p);rules(p,friendlyFire=False);start(p);freeze(p)
  nohit=p.evaluate('''()=>{const T=__test,[a,b]=T.tanks;for(const t of [a,b])Object.assign(t,{team:2,alive:true,shield:5,invulnerable:0});T.hurt(b,{owner:a.id});return b.alive&&b.shield===5}''');check(nohit,'Disabled friendly fire protects teammate and their shield');room(p)
  # Sidebar is not just invisible: it releases the column; fullscreen keeps shapes proportional.
  before=box(p);p.locator('#sidebarBtn').click();p.wait_for_timeout(100);after=box(p)
  check(p.locator('.sidebar').is_hidden() and after['width']>before['width']+180,'Hiding sidebar releases horizontal arena space')
  check(p.locator('#sidebarBtn').get_attribute('aria-expanded')=='false','Sidebar toggle exposes accessible state')
  saved=p.evaluate('({...__store})');q=load(storage=saved);check(q.locator('.sidebar').is_hidden(),'Sidebar preference survives reload through storage');q.close()
  # Native fullscreen test (not a simulated class); possible in headless Chromium.
  p.locator('#fullscreenBtn').click();p.wait_for_timeout(180)
  full=p.evaluate('!!document.fullscreenElement');check(full,'Native fullscreen entered successfully in Chromium')
  check(p.locator('.hero').is_hidden() and p.locator('.footer').is_hidden(),'Fullscreen removes page chrome')
  check(box(p)['width']>=p.viewport_size['width']-32,'Fullscreen hidden-sidebar arena spans viewport')
  p.screenshot(path=str(out/'fullscreen-expanded.png'));p.locator('#fullscreenBtn').click();p.wait_for_timeout(120)
  p.locator('#sidebarBtn').click();check(p.locator('.sidebar').is_visible(),'Sidebar can be restored');p.close()
  # Local CTF/KOTH: tied time triggers final life, not a stale GO or match draw.
  for mode,index in [('ctf',3),('koth',4)]:
   p=load(size=(390,844));preset(p,index);start(p);freeze(p)
   if mode=='ctf':
    p.screenshot(path=str(out/'flag-home-phone.png'))
    p.evaluate('''()=>{const f=__test.localObjectives.flags[1],t=__test.tanks[0];f.carrier=t.id;f.home=false;f.x=t.x;f.y=t.y;}''');p.wait_for_timeout(60);p.screenshot(path=str(out/'flag-carried-phone.png'))
   result=p.evaluate('''()=>{const T=__test;T.setPhase('playing');T.setClock(0);T.tanks[0].alive=false;T.stepLocalObjectives(0);return {state:leqra.getState(),alive:T.tanks.every(t=>t.alive),generation:T.localObjectives.showdown}}''')
   check(result['state']['phase']=='playing' and result['state']['objectives']['suddenDeath'] and result['alive'],mode+' starts sudden death with all final lives')
   p.evaluate("__test.setPhase('paused');__test.updateHUD(true)");check('SUDDEN DEATH' in p.locator('#objectiveModeLabel').inner_text() and p.locator('#announcer').is_hidden(),mode+' persistent unobtrusive sudden-death banner; no GO')
   p.screenshot(path=str(out/f'sudden-death-{mode}.png'))
   dead=p.evaluate('''()=>{const T=__test,t=T.tanks[0];t.invulnerable=0;T.hurt(t,{owner:t.id});T.respawnLocalPlayers(50);T.updateHUD(true);return{alive:t.alive,caption:document.querySelector('#cooldownText1').textContent}}''')
   check(not dead['alive'] and not dead['caption'].startswith('RESPAWN'),mode+' no resurrection or misleading respawn countdown')
   p.evaluate('''()=>{const T=__test;T.setPhase('playing');const winner=T.tanks[1];for(const t of T.tanks)t.alive=t.id===winner.id;T.stepLocalSuddenDeath();}''')
   check(p.locator('#victoryDialog').is_visible() and 'WINS!' in p.locator('#victoryTitle').inner_text(),mode+' surviving side receives victory popup')
   check('sudden death' in p.locator('#victoryMessage').inner_text(),mode+' popup explains survival winner')
   p.screenshot(path=str(out/f'victory-{mode}.png'));closewin(p);check(p.locator('#roomScreen').is_visible(),'Closing victory returns to same room');p.close()
  # Real online host, remote human and named spectator.
  host=load('CAPTAIN');preset(host,2)
  # Free a seat without losing local P2.
  victim=next(v for v in state(host)['room']['players'] if v['kind']=='bot');host.locator(f'#roomRoster [data-kick-target="{victim["id"]}"]').click();host.locator('#confirmKickBtn').click()
  rules(host,mode='ctf',scoreTarget=3,friendlyFire=True,pickupRate='off')
  code='Polish v34 '+str(time.time());host.locator('#localRoomName').fill(code);host.locator('#copyInviteBtn').click();host.wait_for_function('leqra.getState().online?.connected')
  guest=load('FRIEND',code=code);guest.wait_for_function('leqra.getState().online?.connected');host.wait_for_function('leqra.getState().room.players.length===4')
  viewer=load('OBSERVER',size=(320,568),code=code,watch=True);check(not state(viewer)['online'],'Watch link still asks for callsign before joining');viewer.locator('#pilotName').fill('OBSERVER');viewer.locator('#joinRoomBtn').click();viewer.wait_for_function('leqra.getState().online?.spectating')
  guest.locator('#roomRulesBtn').click();check(guest.locator('#rule-friendlyFire').is_disabled() and guest.locator('#rule-friendlyFire').is_checked(),'Guest sees friendly-fire rule but cannot change it');guest.locator('[data-close-dialog="rulesDialog"]').click()
  guest.evaluate('''()=>{const r={...leqra.getState().rules,friendlyFire:false};__sockets.at(-1).send(JSON.stringify({type:'rules',rules:r}))}''');guest.wait_for_function('__messages.some(m=>m.type==="error"&&m.code==="not_host")');check(state(host)['rules']['friendlyFire'],'Server rejects guest-forged friendly-fire change')
  guest.locator('#readyBtn').click();host.wait_for_function('leqra.getState().room.canStart');start(host);viewer.wait_for_function('leqra.getState().phase==="playing"');host.wait_for_timeout(700)
  # Reproduce RAF timestamp before receipt; the old implementation made phaseTime positive.
  go=host.evaluate('''()=>{const T=__test,o=T.online,s=o.snapshots.at(-1);s.phaseTime=0;const saved=s.received;s.received=performance.now()+12;T.renderOnlineMotion(.016,performance.now());T.updateHUD();const r={visible:!document.querySelector('#announcer').hidden,text:document.querySelector('#announceMain').textContent};s.received=saved;return r;}''')
  check(not(go['visible'] and go['text']=='GO'),'Early RAF timestamp cannot resurrect GO banner')
  fixture(code,'kill',0);host.wait_for_timeout(180);check(host.locator('#announcer').is_hidden(),'A CTF death does not retrigger GO')
  fixture(code,'warning',0);host.wait_for_timeout(100);check(host.locator('#announcer').is_hidden(),'Missile proximity does not retrigger GO')
  fixture(code,'tie34');host.wait_for_function('leqra.getState().objectives?.suddenDeath');guest.wait_for_function('leqra.getState().objectives?.suddenDeath');viewer.wait_for_function('leqra.getState().objectives?.suddenDeath')
  check(all(state(x)['phase']=='playing' for x in [host,guest,viewer]),'Online tied timer starts same sudden death for players and spectators')
  check(state(viewer)['online']['spectating'] and all(t['id']<4 for t in state(viewer)['tanks']),'Spectator remains outside final-life lineup')
  # Freeze clients' rendering moment only to inspect stable layout; Go keeps authority.
  viewer.screenshot(path=str(out/'spectator-sudden-death.png'))
  fixture(code,'finish34',0);host.wait_for_function('document.querySelector("#victoryDialog").open');guest.wait_for_function('document.querySelector("#victoryDialog").open');viewer.wait_for_function('document.querySelector("#victoryDialog").open')
  check(all('TEAM 1 WINS!'==x.locator('#victoryTitle').inner_text().upper() for x in [host,guest,viewer]),'Host, guest and spectator congratulate the same winning team')
  check('CAPTAIN' in viewer.locator('#victoryMembers').inner_text() and 'PLAYER 2' in viewer.locator('#victoryMembers').inner_text(),'Victory popup identifies winning team members')
  host.screenshot(path=str(out/'online-victory.png'));closewin(viewer);viewer.wait_for_timeout(300);check(viewer.locator('#victoryDialog').is_hidden(),'Repeated match-over snapshots do not reopen dismissed popup')
  check(state(viewer)['online']['spectating'],'Dismissing victory preserves spectator role')
  closewin(host);closewin(guest);guest.locator('#readyBtn').click();host.wait_for_function('leqra.getState().room.canStart');start(host);viewer.wait_for_function('leqra.getState().phase==="playing"');check(not state(viewer)['objectives']['suddenDeath'] and state(viewer)['online']['spectating'],'Rematch resets sudden death but retains spectators')
  for x in [host,guest,viewer]:x.close()
  check(not errors,'No browser JavaScript errors')
  (out/'results.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'measurements':measurements,'errors':errors},indent=2));print('TOTAL',len(checks),flush=True)
 except Exception:
  for i,c in enumerate(contexts):
   for p in c.pages:
    try:p.screenshot(path=str(out/f'failure-{i}.png'))
    except Exception:pass
  (out/'failure.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'errors':errors,'measurements':measurements},indent=2));raise
 finally:browser.close()

"""v3.2 UI/local simulation and real Go-backed objective tests.
Uses shipped assets with Location/History/storage adapters because navigation is
blocked in the execution environment. The fixture server is opt-in and loopback-only.
"""
import argparse,json,re,time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8878');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/features32');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def dismissVictory(p):
 if p.locator('#victoryDialog').count() and p.locator('#victoryDialog').is_visible():p.locator('#victoryCloseBtn').click()
def check(v,label):
 if not v:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def fixture(code,action,player=0):
 with urlopen(Request(args.url+'/_fixture/features32',data=json.dumps(dict(code=code,action=action,player=player)).encode(),headers={'Content-Type':'application/json'}),timeout=5) as r:return json.load(r)
def lane(p):
 p.evaluate('''()=>{const T=__test,w=leqra.getState().world;T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{x:150,y:90+i*110,angle:0,invulnerable:100,cooldown:99,alive:true}));T.clearInput();}''')
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[]
 def load(name='HOST',code=None,size=(1365,950),storage=None):
  mobile=size[0]<760 or size[1]<620;ctx=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(ctx)
  p=ctx.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code}) if code else '')
  p.evaluate(r'''([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied='';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=(data)=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({'leqra.name':name,'leqra.muted':'1'},storage||{});Object.defineProperty(window,'localStorage',{value:store(__store)});Object.defineProperty(window,'sessionStorage',{value:store({})});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{__copied=v}}});}''',[url,args.url.replace('http:','ws:')+'/ws',name,storage])
  js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
  p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def close(p,kind):p.locator('[data-close-dialog="'+kind+'Dialog"]').click()
 def preset(p,index):dismissVictory(p);p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('builtin:'+str(index));p.locator('#loadPresetBtn').click();p.wait_for_function('!document.querySelector("#presetsDialog").open')
 def start(p):dismissVictory(p);p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=9000)
 def room(p):dismissVictory(p);p.locator('#roomBtn').click();p.locator('#returnRoomBtn').click();p.wait_for_function('["menu","onlineLobby"].includes(leqra.getState().phase)')
 def press(p,key,ms=40):p.keyboard.down(key);p.wait_for_timeout(ms);p.keyboard.up(key)
 def rules(p,**values):
  dismissVictory(p)
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
  for key,val in values.items():
   loc=p.locator('#rule-'+key)
   if key in ['teamMode','mapSize','pickupRate']:
    if not loc.is_disabled():loc.select_option(str(val));p.wait_for_timeout(20)
    else:assert loc.input_value()==str(val)
   else:loc.fill(str(val))
  p.locator('#applyRulesBtn').click();p.wait_for_function('!document.querySelector("#rulesDialog").open')
 def screenshot(p,name):p.screenshot(path=str(out/(name+'.png')))
 # New default controls and safe UI grouping.
 p=load();check(state(p)['rules']['mode']=='elimination','Default room keeps elimination rules')
 check(p.locator('#roomRulesBtn').is_visible() and p.locator('#roomPresetsBtn').is_visible() and p.locator('#roomControlsBtn').is_visible(),'Rules, presets and controls are separate room panels')
 p.locator('#addLocalBtn').click();check(state(p)['room']['players'][-1]['id']==3,'New P2 keeps sparse seat identity')
 p.locator('#roomControlsBtn').click();check(p.locator('[data-bind="0:fire"]').inner_text()=='F' and p.locator('[data-bind="1:fire"]').inner_text()=='SPACE','Default P1 F and P2 Space shown in remapper')
 close(p,'controls');start(p);lane(p)
 p.evaluate('''()=>{for(const t of __test.tanks.filter(t=>t.human)){t.cooldown=0;__test.grantPower(t,'grenade');t.charges=1;}}''')
 press(p,'Enter');check(p.evaluate('__test.bullets.length===0'),'Enter no longer fires the secondary tank')
 press(p,'Space');check(p.evaluate('__test.bullets.filter(b=>b.kind==="grenade").length===1&&__test.bullets[0].owner===3'),'Space throws only the secondary tank grenade')
 press(p,'Space');check(p.evaluate('__test.bullets.length===0'),'Space detonates secondary final grenade without P1 crosstalk')
 press(p,'KeyF');check(p.evaluate('__test.bullets.some(b=>b.kind==="grenade"&&b.owner===0)'),'F fires the primary tank independently')
 check(p.locator('#cooldownText1').inner_text()=='DETONATE READY','Cooldown feedback prioritizes armed remote grenade')
 press(p,'KeyF');room(p)
 # Remapping conflicts, cancellation, persistence and actual controls.
 p.locator('#roomControlsBtn').click();p.locator('[data-bind="1:fire"]').click();p.keyboard.press('KeyF')
 check('already assigned' in p.locator('#controlsNotice').inner_text() and p.evaluate('__test.bindings[1].fire')=='Space','Conflicting key rejected without modifying either player')
 p.keyboard.press('KeyP');check('reserved' in p.locator('#controlsNotice').inner_text(),'Pause key cannot be rebound')
 p.keyboard.press('KeyL');check(p.evaluate('__test.bindings[1].fire')=='KeyL','Secondary fire can be rebound')
 p.locator('[data-bind="0:forward"]').click();p.keyboard.press('Escape');check(p.evaluate('__test.bindings[0].forward')=='KeyW','Escape cancels key capture without modifying movement')
 check('leqra.bindings.v1' in p.evaluate('Object.keys(__store)'),'Bindings saved in device storage')
 saved=p.evaluate('({...__store})');close(p,'controls');start(p);lane(p)
 p.evaluate('''()=>{let t=__test.tanks[3];t.cooldown=0;__test.grantPower(t,'grenade');}''');press(p,'Space');check(p.evaluate('__test.bullets.length===0'),'Old secondary fire key stops firing after remapping')
 press(p,'KeyL');check(p.evaluate('__test.bullets.some(b=>b.owner===3)'),'Remapped fire launches on actual gameplay path')
 check('L' in p.locator('#pilotLoadout2 .loadout-key').inner_text(),'Secondary HUD reflects remapped fire key')
 room(p);q=load(storage=saved);check(q.evaluate('__test.bindings[1].fire')=='KeyL','A fresh page restores saved bindings');q.close()
 p.locator('#roomControlsBtn').click();p.locator('#resetBindingsBtn').click();check(p.evaluate('__test.bindings[1].fire')=='Space','Reset defaults restores secondary Space')
 p.locator('#missileAudio').uncheck();p.locator('#missileAudio').check();check(json.loads(p.evaluate('__store["leqra.feedback.v1"]'))['audio'],'Optional lock warning audio preference persists');close(p,'controls')
 # Local global FFA and configured map/weapon rates.
 rules(p,teamMode='ffa',mapSize='compact',scoreTarget=2,timeLimit=40,pickupRate='off')
 check(all(x['team']==0 for x in state(p)['room']['players']),'Host Free-for-all applies to every tank')
 check(p.locator('#roomRoster [data-team]').count()>0 and p.locator('#roomRoster [data-team]:enabled').count()==0,'FFA locks all individual team selectors')
 start(p);check(state(p)['world']['cols']==7 and state(p)['world']['rows']==7,'Compact host map rule changes actual maze')
 check(state(p)['pickupCount']==0 and 38<state(p)['roundClock']<=40,'Off rule removes starting pickups and clock uses host limit');room(p)
 rules(p,teamMode='teams');check([x['team'] for x in state(p)['room']['players']]==[1,2,2,1],'Switching out of FFA restores sensible sides and unlocks selectors')
 check(p.locator('#roomRoster [data-team]:enabled').count()==4,'Host can edit all teams in Teams format')
 # Presets, storage validation and local mode setup.
 dismissVictory(p);p.locator('#roomPresetsBtn').click();check(p.locator('#presetSelect optgroup').count()==2 and p.locator('#presetSelect option').count()==5,'Five built-in presets offered separately from saved presets')
 p.locator('#presetName').fill('My squad 💥');p.locator('#savePresetBtn').click();check('Preset saved' in p.locator('#presetsNotice').inner_text(),'Named custom room preset saved')
 data=json.loads(p.evaluate('__store["leqra.presets.v1"]'));check(data['items'][0]['roster'][3]['kind']=='local' and data['items'][0]['rules']['mapSize']=='compact','Preset includes secondary player and match rules')
 check('token' not in json.dumps(data) and 'member' not in json.dumps(data),'Saved preset contains no sessions or runtime identities')
 close(p,'presets');preset(p,0);check(len(state(p)['room']['players'])==2 and state(p)['room']['players'][1]['difficulty']=='easy','Solo Practice loads easy bot and compact maze')
 dismissVictory(p);p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('saved:0');p.locator('#loadPresetBtn').click();check(len(state(p)['room']['players'])==4 and state(p)['rules']['pickupRate']=='off','Saved setup restores full roster and weapon frequency')
 persist=p.evaluate('({...__store})');q=load(storage=persist);dismissVictory(q);q.locator('#roomPresetsBtn').click();check(q.locator('#presetSelect option[value="saved:0"]').inner_text()=='My squad 💥','Saved presets survive loading a fresh page');q.locator('#presetSelect').select_option('saved:0');q.locator('#deletePresetBtn').click();check(q.locator('#presetSelect option[value="saved:0"]').count()==0,'Saved preset can be deleted with confirmation');q.close()
 q=load(storage={'leqra.bindings.v1':'{"bindings":[null]}','leqra.presets.v1':'broken'});check(q.evaluate('__test.bindings[1].fire')=='Space','Invalid storage falls back to safe defaults');q.close()
 # Feedback tested directly against actual rendering with stable local test state.
 preset(p,2);start(p);lane(p)
 feedback=p.evaluate('''()=>{const t=__test.tanks[0],p2=__test.tanks[1];__test.clearBullets();Object.assign(t,{cooldown:.5,cooldownTotal:1,power:'laser',charges:3});Object.assign(p2,{cooldown:0,power:null});__test.addBullet({owner:2,target:0,kind:'homing',x:t.x+60,y:t.y,vx:-235,vy:0,r:4,life:5,age:1,rangeLeft:900,seekDelay:1,trail:[],color:'#fff'});__test.updateCombatFeedback();return {warning:!document.querySelector('#missileWarning1').hidden,p2hidden:document.querySelector('#missileWarning2').hidden,cd:document.querySelector('#cooldownText1').textContent,progress:document.querySelector('#cooldownTrack1').getAttribute('aria-valuenow')};}''')
 check(feedback['warning'] and feedback['p2hidden'],'Only the missile-targeted local player sees a lock warning')
 check(feedback['cd']=='COOLDOWN 0.5s' and feedback['progress']=='50','Cooldown text and fill expose accurate time/progress')
 p.evaluate('''()=>{__test.clearBullets();__test.tanks[0].cooldown=0;__test.updateCombatFeedback()}''');check(p.locator('#missileWarning1').is_hidden(),'Missile warning clears when lock disappears')
 # Seed expired ammo / independent tank feedback without waiting for simulation.
 ammo=p.evaluate('''()=>{const t=__test.tanks[1];t.power=null;t.cooldown=0;for(let i=0;i<5;i++)__test.addBullet({id:100+i,kind:'standard',owner:t.id,dead:false});__test.updateCombatFeedback();const a=document.querySelector('#cooldownText2').textContent;__test.clearBullets();return a;}''')
 check(ammo=='WAITING FOR AMMO','Exhausted projectile slots show explicit wait status')
 check(p.locator('#pilotLoadout2').is_visible(),'Both local players keep independent ammo/cooldown panels');room(p)
 # Actual local objective state machine, no replacement simulation.
 preset(p,3);check(state(p)['rules']['mode']=='ctf' and len(set(x['team'] for x in state(p)['room']['players']))==2,'Capture preset supplies two valid teams')
 rules(p,scoreTarget=2,respawnSeconds=1,pickupRate='off');start(p);lane(p)
 check(p.locator('#objectiveBar').is_visible() and 'CAPTURE' in p.locator('#objectiveModeLabel').inner_text(),'Capture mode shows in-game objective bar')
 capture=p.evaluate('''()=>{const o=__test.localObjectives,t=__test.tanks[0],f=o.flags.find(f=>f.team!==t.team),home=o.flags.find(f=>f.team===t.team);t.invulnerable=0;t.x=f.x;t.y=f.y;__test.stepLocalObjectives(.01);const stolen=f.carrier===t.id;t.x=home.homeX;t.y=home.homeY;__test.stepLocalObjectives(.01);return{stolen,home:f.home,scores:leqra.getState().scores};}''')
 check(capture['stolen'] and capture['home'],'Local CTF supports actual pickup and capture')
 check(capture['scores'][0]==1 and capture['scores'][1]==1 and capture['scores'][2]==0,'CTF point is shared only with teammates')
 resp=p.evaluate('''()=>{const t=__test.tanks[0],f=__test.localObjectives.flags.find(f=>f.team!==t.team);Object.assign(f,{carrier:t.id,home:false,x:t.x,y:t.y});t.invulnerable=0;__test.hurt(t,{owner:2});__test.updateCombatFeedback();const before={dead:!t.alive,dropped:f.carrier<0&&!f.home,caption:document.querySelector('#cooldownText1').textContent};__test.respawnLocalPlayers(1.1);return{...before,alive:t.alive,serial:t.spawnSerial,shield:t.invulnerable};}''')
 check(resp['dead'] and resp['dropped'] and resp['alive'] and resp['shield']>0,'CTF death drops the flag and configured respawn restores protected tank')
 check(resp['caption'].startswith('RESPAWN '),'Dead player sees respawn countdown instead of empty ready message')
 p.evaluate('''()=>{const t=__test.tanks[0],o=__test.localObjectives,own=o.flags.find(f=>f.team===t.team),enemy=o.flags.find(f=>f.team!==t.team);t.invulnerable=0;t.x=own.homeX;t.y=own.homeY;Object.assign(enemy,{carrier:0,home:false});__test.stepLocalObjectives(.01);}''');check(state(p)['phase']=='matchOver' and state(p)['scores'][0]==2,'CTF ends at capture target without an extra elimination point')
 # End match modal already room; room controls visible in matchOver.
 preset(p,4);rules(p,scoreTarget=3,respawnSeconds=1,pickupRate='off');start(p);lane(p)
 hill=p.evaluate('''()=>{const o=__test.localObjectives,t=__test.tanks[0];t.invulnerable=0;t.x=o.hillX-16;t.y=o.hillY;__test.stepLocalObjectives(1.05);const a=leqra.getState().scores[0];const u=__test.tanks[1];u.invulnerable=0;u.x=o.hillX+16;u.y=o.hillY;__test.stepLocalObjectives(1.2);return {first:a,after:leqra.getState().scores[0],contested:o.contested};}''')
 check(hill['first']==1 and hill['after']==1 and hill['contested'],'Local KOTH awards timed points and pauses while contested')
 p.evaluate('''()=>{const o=__test.localObjectives;__test.tanks[1].x=60;__test.stepLocalObjectives(2.05)}''');check(state(p)['phase']=='matchOver' and state(p)['scores'][0]==3,'KOTH reaches its point target rather than ending on a kill')
 # Browser reload storage says preset intact; objective start validity.
 rules(p,mode='ctf');p.locator('#roomRoster [data-team="0"]').select_option('0');check(p.locator('#startRoomBtn').is_disabled(),'CTF refuses FFA/invalid roster until host assigns exactly two numbered teams')
 preset(p,0)
 # Real Go-backed lobby, guest permissions, rules broadcast and shared objectives.
 code='Objective32 '+str(time.time_ns())+' ⚑';p.locator('#localRoomName').fill(code);p.locator('#copyInviteBtn').click();p.wait_for_function('leqra.getState().online?.connected')
 q=load('GUEST',code,(390,844));q.wait_for_function('leqra.getState().online?.connected');p.wait_for_function('leqra.getState().room.players.length===3')
 check(q.locator('#roomPresetsBtn').is_disabled() and q.locator('#roomRulesBtn').inner_text()=='VIEW RULES','Guest can inspect rules but cannot load host presets')
 dismissVictory(q);q.locator('#roomRulesBtn').click();check(q.locator('#rulesFields').evaluate('(e)=>e.disabled') and q.locator('#applyRulesBtn').is_disabled(),'Guest rules fields are read-only');close(q,'rules')
 q.evaluate('''()=>__sockets.at(-1).send(JSON.stringify({type:'rules',rules:{...leqra.getState().rules,teamMode:'ffa'}}))''');q.wait_for_function('__messages.some(m=>m.type==="error"&&m.code==="not_host")');check(state(p)['rules']['teamMode']=='teams','Go rejects a forged guest Free-for-all command')
 rules(p,teamMode='ffa');q.wait_for_function('leqra.getState().rules.teamMode==="ffa"');check(all(x['team']==0 for x in state(q)['room']['players']),'Online Free-for-all applies and broadcasts to all players')
 check(q.locator('#roomRoster select').count()==0 and p.locator('#roomRoster [data-team]:enabled').count()==0,'Neither guest nor host seat selector can pick teams under FFA')
 dismissVictory(p);p.locator('#roomPresetsBtn').click();check(p.locator('#loadPresetBtn').is_disabled(),'Preset loading refuses to replace a remote guest');p.locator('#presetName').fill('Shared setup');p.locator('#savePresetBtn').click();savedonline=json.loads(p.evaluate('__store["leqra.presets.v1"]'));check(all(x['name']!='GUEST' for x in savedonline['items'][-1]['roster']),'Saving an online preset omits remote guests');close(p,'presets')
 rules(p,mode='ctf',teamMode='teams',scoreTarget=2,respawnSeconds=1,pickupRate='off',mapSize='large')
 # Team conversion assigned guest2 bot2, host1 -> valid and least-populated join protected.
 q.wait_for_function('leqra.getState().rules.mode==="ctf"');dismissVictory(q);q.locator('#readyBtn').click();p.wait_for_function('leqra.getState().room.canStart');start(p);q.wait_for_function('leqra.getState().phase==="playing"')
 check(state(p)['world']['cols']==12 and state(q)['world']['cols']==12,'Host-selected large map is authoritative for both browsers')
 check(len(state(p)['objectives']['flags'])==2 and state(q)['objectives']['mode']=='ctf','Go sends complete objective state to host and guest')
 fixture(code,'capture');p.wait_for_function('leqra.getState().scores[0]===1');q.wait_for_function('leqra.getState().scores[0]===1');check(True,'Server capture score arrives identically at host and guest')
 fixture(code,'kill');p.wait_for_function('!leqra.getState().tanks.find(t=>t.id===0).alive');check('RESPAWN' in p.locator('#cooldownText1').inner_text(),'Authoritative death exposes the respawn countdown')
 p.wait_for_function('leqra.getState().tanks.find(t=>t.id===0).alive&&leqra.getState().tanks[0].spawnSerial>=2',timeout=5000);check(True,'Server respawn increments epoch and restores controlled tank')
 fixture(code,'capture');p.wait_for_function('leqra.getState().phase==="matchOver"');q.wait_for_function('leqra.getState().phase==="matchOver"');check(state(p)['scores'][0]==2,'Online CTF finishes at configured target on all clients')
 rules(p,mode='koth',teamMode='ffa',scoreTarget=8,respawnSeconds=1,pickupRate='off')
 q.wait_for_function('leqra.getState().rules.mode==="koth"');dismissVictory(q);q.locator('#readyBtn').click();p.wait_for_function('leqra.getState().room.canStart');start(p);q.wait_for_function('leqra.getState().phase==="playing"')
 fixture(code,'hill');p.wait_for_function('leqra.getState().scores[0]>=1',timeout=4000);s=state(p)['scores'][0];fixture(code,'contested');p.wait_for_function('leqra.getState().objectives.contested');p.wait_for_timeout(1100)
 check(state(p)['scores'][0]==s and state(q)['objectives']['contested'],'Real Go hill stops scoring with an opponent present')
 check('CONTESTED' in p.locator('#objectiveStatus').inner_text(),'Online objective HUD reports contested hill')
 screenshot(p,'online-hill-desktop');room(p);q.wait_for_function('leqra.getState().phase==="onlineLobby"');check(state(q)['scores'][0]==0,'Host can end objective match and reset scores without losing room')
 # Newly default P2 Space travels over independent owned network controls.
 p.locator('#addLocalBtn').click();p.wait_for_function('leqra.getState().room.players.some(p=>p.kind==="local")');lid=next(x['id'] for x in state(p)['room']['players'] if x['kind']=='local')
 dismissVictory(q);q.locator('#readyBtn').click();p.wait_for_function('leqra.getState().room.canStart');start(p);q.wait_for_function('leqra.getState().phase==="playing"')
 press(p,'Space');check(p.evaluate('id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.fire)',lid),'Space is sent as secondary owned Fire input online')
 press(p,'KeyF');check(p.evaluate('__sent.some(m=>m.type==="input"&&(m.player??0)===0&&m.fire)'),'F is independently sent for online primary Fire')
 room(p);q.close();p.close()
 # Responsive configuration + objective play, all actions hit-testable after scroll.
 for size in [(320,568),(390,844),(844,390),(1365,950)]:
  p=load(size=size);preset(p,3)
  for button in ['roomRulesBtn','roomPresetsBtn','roomControlsBtn','startRoomBtn']:
   p.locator('#'+button).scroll_into_view_if_needed();hit=p.locator('#'+button).evaluate('(e)=>{const r=e.getBoundingClientRect();const h=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return h===e||e.contains(h)}');check(hit,f'{size}: {button} reachable and not covered')
  dismissVictory(p);p.locator('#roomMapSize').select_option('compact');p.wait_for_function('(value)=>leqra.getState().rules.mapSize===value',arg='compact');p.locator('#roomRulesBtn').click();p.locator('#applyRulesBtn').scroll_into_view_if_needed();check(p.locator('#applyRulesBtn').is_visible(),f'{size}: rules form scrolls to Apply');screenshot(p,f'rules-{size[0]}x{size[1]}');p.locator('#applyRulesBtn').click()
  p.locator('#roomControlsBtn').click();p.locator('[data-bind="1:fire"]').click();p.keyboard.press('KeyL');check(p.locator('[data-bind="1:fire"]').inner_text()=='L',f'{size}: remapping works in compact dialog');screenshot(p,f'controls-{size[0]}x{size[1]}');close(p,'controls')
  dismissVictory(p);p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('Responsive setup');p.locator('#savePresetBtn').click();check('saved' in p.locator('#presetsNotice').inner_text().lower(),f'{size}: custom preset can be saved');close(p,'presets')
  p.locator('#roomScreen').evaluate('(e)=>e.scrollTop=0');screenshot(p,f'room-{size[0]}x{size[1]}');start(p)
  check(state(p)['world']['cols']==7 and p.locator('#objectiveBar').is_visible(),f'{size}: objective match renders compact maze and HUD')
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'{size}: no horizontal page overflow')
  if size[0]<760 or size[1]<620:
   a=p.locator('#stickBase').bounding_box();b=p.locator('#fireBtn').bounding_box();cdp=p.context.new_cdp_session(p);cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':a['x']+a['width']/2+20,'y':a['y']+a['height']/2,'id':71},{'x':b['x']+b['width']/2,'y':b['y']+b['height']/2,'id':72}]});p.wait_for_timeout(150);cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});check(True,f'{size}: simultaneous touch events remain handled')
  screenshot(p,f'playing-{size[0]}x{size[1]}');p.close()
 check(not errors,'No JavaScript page errors across new feature tests')
 browser.close();report={'version':'3.2.0','checks_passed':len(checks),'checks':checks,'page_errors':errors,'limits':'Chromium emulation; exact assets, synthetic Location/History/storage, real loopback Go fixture. No physical devices/public internet.'};(out/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':len(checks),'errors':errors}))

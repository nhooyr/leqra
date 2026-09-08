"""v3.6: exact browser assets, local simulation and loopback Go snapshots.
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
  names=['Aurora 🌟','<b>Fire</b>','Tidal & Co','Violet Guard']
  for size in [(1365,950),(320,568),(844,390)]:
   p=load(size=size);r=state(p)
   check(r['rules']['teamMode']=='ffa' and r['rules']['mapSize']=='large','Default FFA / 12x10 '+str(size))
   check(len(r['room']['players'])==4 and sum(t['kind']=='bot' and t['difficulty']=='normal' for t in r['room']['players'])==3,'Default three Normal bots '+str(size))
   check(all(t['team']==0 for t in r['room']['players']) and p.evaluate('__sockets.length')==0,'Default four independent opponents, no network connection '+str(size))
   p.locator('#addLocalBtn').click()
   while len(state(p)['room']['players'])<8:p.locator('#addBotBtn').click()
   check(all(t['team']==0 for t in state(p)['room']['players']),'Add bot/P2 never groups FFA tanks '+str(size))
   rules(p,teamMode='teams',**{'teamName'+str(i+1):n for i,n in enumerate(names)})
   check(state(p)['rules']['teamNames']==names,'Four custom names accepted '+str(size))
   check(p.locator('[data-team]').first.evaluate('(e)=>[...e.options].map(o=>o.value)')==['1','2','3','4'],'Teams dropdown has exactly four choices '+str(size))
   check(p.locator('[data-team]').first.evaluate('(e)=>e.options[1].textContent')=='<b>Fire</b> · T2' and not p.locator('[data-team] b').count(),'Team names are literal text, not HTML '+str(size))
   check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No horizontal overflow with team names '+str(size))
   p.locator('#roomRulesBtn').click();p.screenshot(path=str(out/f'team-settings-{size[0]}.png'));p.locator('[data-close-dialog="rulesDialog"]').click()
   rules(p,mode='ctf',timeLimit=600,scoreTarget=20);start(p);freeze(p)
   spawnOK=p.evaluate('''()=>{const T=__test,o=T.localObjectives;for(let k=0;k<12;k++)for(const t of T.tanks){t.alive=false;T.respawnLocalTank(t);const f=o.flags.find(f=>f.team===t.team),w=leqra.getState().world;if(Math.floor(t.x/84)===Math.floor(f.homeX/84)&&Math.floor(t.y/84)===Math.floor(f.homeY/84)||Math.hypot(t.x-f.x,t.y-f.y)<t.r+32)return false;}return true}''')
   check(spawnOK,'Eight tanks never spawn in their flag cell '+str(size))
   # Prove actual painter's order: a tank interior is identical with/without its
   # oversized flag marker underneath. The card is deliberately overlapped.
   pixels=p.evaluate('''()=>{const T=__test,o=T.localObjectives,f=o.flags[0],t=T.tanks.find(t=>t.team===f.team),v=T.view,w=leqra.getState().world,z=Math.max(1.35,1/v.scale),clamp=(x,a,b)=>Math.max(a,Math.min(b,x));t.x=clamp(f.x,40*z,w.width-40*z);t.y=clamp(f.y-12*z,26*z,w.height-36*z);t.angle=0;t.recoil=0;t.shield=t.speedTime=t.invulnerable=0;T.clearBullets();const canvas=document.querySelector('#arena'),c=canvas.getContext('2d'),d=canvas.width/v.cssW;const crop=()=>Array.from(c.getImageData(Math.round((v.offsetX+(t.x-10)*v.scale)*d),Math.round((v.offsetY+(t.y-5)*v.scale)*d),Math.max(1,Math.floor(18*v.scale*d)),Math.max(1,Math.floor(10*v.scale*d))).data);T.render();const a=crop(),flags=o.flags;o.flags=[];T.render();const b=crop();o.flags=flags;T.render();return a.every((v,i)=>v===b[i]);}''')
   check(pixels,'Flag cannot cover ally hull: pixel comparison '+str(size))
   before=box(p);p.evaluate("()=>{for(const t of __test.tanks)if(t.human){__test.grantPower(t,'speed');t.shield=10;}__test.updateHUD(true)}");p.wait_for_timeout(70);check(box(p)==before,'Buffs retain stable maze dimensions '+str(size))
   check(p.locator('#pilotLoadout2').is_visible(),'Player 2 retains own ammo '+str(size))
   p.screenshot(path=str(out/f'flags-behind-tanks-{size[0]}.png'))
   room(p);p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('Named teams 36');p.locator('#savePresetBtn').click()
   store=p.evaluate('__store');saved=json.loads(store['leqra.presets.v1'])['items'][0];check(saved['rules']['teamNames']==names,'Preset includes all four names '+str(size));p.close()
  # Persistent names, Unicode limits, and migration of old Independent presets.
  p=load(storage=store);p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('saved:0');p.locator('#loadPresetBtn').click();check(state(p)['rules']['teamNames']==names,'Reloaded browser preset restores names');
  result=p.evaluate('''()=>{const T=__test,r=T.currentRules(),old={name:'Legacy',rules:{...r,teamMode:'teams'},roster:[{kind:'human',name:'P1',team:0},{kind:'bot',name:'BOT',difficulty:'normal',team:0}]};delete old.rules.teamNames;const p=T.validatePreset(old);return p.roster.map(p=>p.team).join(',')==='1,2'&&p.rules.teamNames.join(',')==='Team 1,Team 2,Team 3,Team 4';}''');check(result,'Legacy Independent presets migrate into numbered teams')
  bad=p.evaluate(r'''()=>{let bad=[[],['A','B'],['\n','B','C','D'],['\u200b','B','C','D'],['x'.repeat(25),'B','C','D']];return bad.every(teamNames=>{try{__test.validateRoomRules({...__test.currentRules(),teamNames});return false}catch(_){return true}});}''');check(bad,'Browser validates count, visibility, length and controls')
  check(p.evaluate('''()=>{const r=__test.validateRoomRules({...__test.currentRules(),teamNames:['💥'.repeat(24),' B ','C','D']});return r.teamNames[0].length===48&&r.teamNames[1]==='B';}'''),'24 emoji codepoints and outer-space trim agree with server');p.close()
  # Local deadline and death audit in controlled open worlds, via shipped physics.
  for mode in ['ctf','koth']:
   p=load();preset(p,3 if mode=='ctf' else 4);start(p);freeze(p)
   audit=p.evaluate('''mode=>{const T=__test,s=leqra.getState(),w=s.world;T.setWorld({...w,walls:[]});T.clearBullets();T.setPhase('playing');for(const t of T.tanks){t.human=true;t.cooldown=999;t.invulnerable=0;t.speedTime=0;t.x=200+t.id*100;t.y=250;}const o=T.localObjectives,a=T.tanks[0];if(mode==='ctf'){const f=o.flags.find(f=>f.team===a.team),enemy=o.flags.find(f=>f.team!==a.team);a.x=f.homeX;a.y=f.homeY;Object.assign(enemy,{carrier:a.id,home:false,x:a.x,y:a.y});T.setClock(0);}else{a.x=o.hillX;a.y=o.hillY;o.owner=-a.id-1;o.hold=.996;T.setClock(.001);}T.update(1/120);T.setPhase('paused');return {scores:leqra.getState().scores,sd:T.localObjectives.suddenDeath};}''',mode)
   check(not any(audit['scores']) and audit['sd'],'No post-deadline '+mode+' point; tie enters sudden death');p.close()
  p=load();preset(p,4);start(p);freeze(p)
  audit=p.evaluate('''()=>{const T=__test,w=leqra.getState().world;T.setWorld({...w,walls:[]});T.setPhase('playing');T.setClock(100);for(const t of T.tanks){t.human=true;t.cooldown=999;t.x=300+t.id*100;t.y=250;}T.tanks[1].x=T.tanks[0].x;T.update(1/120);T.setPhase('paused');return Math.hypot(T.tanks[0].x-T.tanks[1].x,T.tanks[0].y-T.tanks[1].y)>=33.99;}''');check(audit,'Coincident local tanks separate instead of remaining stacked')
  audit=p.evaluate('''()=>{const T=__test;t=T.tanks[0];T.setPhase('matchOver');const before=JSON.stringify(leqra.getState().scores);T.addObjectivePoint(t);return before===JSON.stringify(leqra.getState().scores)}''');check(audit,'Objective points remain frozen after match completion');p.close()
  # Local actual map/spawn breadth beyond the viewport cases above.
  p=load();preset(p,3)
  for size in ['compact','standard','large','huge']:
   result=p.evaluate('''size=>{const T=__test;T.setLocalRules({...T.currentRules(),mapSize:size});for(let seed=0;seed<10;seed++){T.startRound();const o=T.localObjectives;for(const t of T.tanks){const f=o.flags.find(f=>f.team===t.team);if(Math.floor(t.x/84)===Math.floor(f.homeX/84)&&Math.floor(t.y/84)===Math.floor(f.homeY/84))return false;}}T.setPhase('menu');return true}''',size);check(result,'Seeded CTF start placement '+size)
  p.close()
  # Shared room: configured names/format, 8 participants, overflow viewer.
  host=load();code='Teams v36 🌟 '+str(time.time_ns());host.locator('#addLocalBtn').click()
  while len(state(host)['room']['players'])<7:host.locator('#addBotBtn').click()
  rules(host,teamMode='teams',mode='ctf',scoreTarget=2,timeLimit=600,**{'teamName'+str(i+1):n for i,n in enumerate(names)})
  host.locator('#localRoomName').fill(code);host.locator('#copyInviteBtn').click();host.wait_for_function('leqra.getState().online.connected')
  check(state(host)['rules']['teamNames']==names,'Publishing transfers team names to Go')
  guest=load('GUEST',code=code);guest.wait_for_function('leqra.getState().online.connected');check(state(guest)['online']['id']==7,'Guest takes eighth tank')
  view=load('VIEWER',size=(320,568),code=code);view.wait_for_function('leqra.getState().online.connected');check(state(view)['online']['spectating'],'Full eight-tank room still welcomes spectator')
  guest.locator('#roomRulesBtn').click();check(guest.locator('#rule-teamName1').is_disabled(),'Guest cannot edit team-name fields');guest.locator('[data-close-dialog="rulesDialog"]').click()
  check(names[0] in guest.locator('#roomRoster').inner_text(),'Custom team name visible to guest')
  guest.locator('#readyBtn').click();host.wait_for_function('leqra.getState().room.canStart');start(host);view.wait_for_function('leqra.getState().phase==="playing"')
  state1=state(host);check(len(state1['tanks'])==8,'Eight authoritative CTF tanks')
  # Inspect the very first authoritative state: bots have not yet moved.
  check(host.evaluate('''()=>{const s=__messages.find(m=>m.type==='state'&&m.phase==='countdown'&&m.objectives?.flags?.length);return s.tanks.every(t=>{const f=s.objectives.flags.find(f=>f.team===t.team);return Math.floor(t.x/84)!==Math.floor(f.homeX/84)||Math.floor(t.y/84)!==Math.floor(f.homeY/84);});}'''),'Online initial tank spawns avoid flags')
  for i in range(2):fixture(code,'capture',0);host.wait_for_timeout(180)
  host.wait_for_function('document.querySelector("#victoryDialog").open');view.wait_for_function('document.querySelector("#victoryDialog").open')
  check(names[0] in host.locator('#victoryTitle').inner_text(),'Winning popup uses custom team name');check(names[0] in view.locator('#victoryTitle').inner_text(),'Spectators see custom winning team name')
  check(not view.locator('#victoryDialog b').count(),'Markup team name is not inserted as HTML')
  view.screenshot(path=str(out/'online-named-victory-320.png'))
  for q in [host,guest,view]:q.close()
  p=load();start(p);freeze(p)
  check(p.evaluate('''()=>{const T=__test,t=T.tanks[1];for(let i=0;i<260;i++){const copy={...t,name:'CACHE '+i,color:'#'+(0x100000+i*577).toString(16).padStart(6,'0'),track:i*2};T.drawTank(copy);}return T.renderStats.hullEntries<=96&&T.renderStats.labelEntries<=192;}'''),'Sprite and label caches stay bounded with changing colors/names');p.close()
  check(not errors,'No JavaScript exceptions across local/online trials')
  (out/'results.json').write_text(json.dumps({'version':'3.7.1','passed':len(checks),'checks':checks,'errors':errors},indent=2));print('TOTAL',len(checks),flush=True)
 except Exception:
  for i,c in enumerate(contexts):
   for p in c.pages:
    try:p.screenshot(path=str(out/f'failure-{i}.png'))
    except Exception:pass
  (out/'failure.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'errors':errors},indent=2));raise
 finally:browser.close()

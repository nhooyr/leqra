"""v3.1 controls, HUD, and grenade impacts; exact-asset Chromium integration against opt-in loopback Go fixture.
No production test endpoints. Navigation/History are adapters in this environment.
Run LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 go test -run '^TestBrowserFixture$' -timeout 30m
"""
import argparse,json,re,time,math
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:18790');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/unified-room');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(v,label):
 if not v:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def fixture(code,path='lane',**extra):
 with urlopen(Request(args.url+'/_fixture/'+path,data=json.dumps(dict(code=code,**extra)).encode(),headers={'Content-Type':'application/json'}),timeout=5) as r:return json.load(r)
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[]
 def load(name='PILOT',code=None,size=(1365,950),session=None,delay=0):
  mobile=size[0]<760 or size[1]<620
  ctx=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(ctx)
  p=ctx.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>')
  p.set_content(html);url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code}) if code is not None else '')
  p.evaluate(r'''([url,ws,name,session,delay])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied='';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;
   window.WebSocket=class extends RealSocket{
    constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)));}
    send(v){__sent.push(JSON.parse(v));return super.send(v)}
   };
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,'localStorage',{value:store({'leqra.name':name,'leqra.muted':'1'})});
   Object.defineProperty(window,'sessionStorage',{value:store(session?{'leqra.session':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{__copied=v}}});
  }''',[url,args.url.replace('http:','ws:')+'/ws',name,session,delay])
  js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
  p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def remove(p,id):
  p.locator(f'#roomRoster [data-kick-target="{id}"]').click();p.locator('#confirmKickBtn').click();p.wait_for_function('id=>!leqra.getState().room.players.some(p=>p.id===id)',arg=id)
 def waitplayers(p,n):p.wait_for_function('n=>leqra.getState().room.players.length===n',arg=n)
 def press(p,key,ms=80):p.keyboard.down(key);p.wait_for_timeout(ms);p.keyboard.up(key)
 def connected(p):p.wait_for_function('leqra.getState().online?.connected',timeout=12000)
 def latest(p):return p.evaluate('__messages.filter(m=>m.type==="state").at(-1)')
 def menu(p):p.locator('#roomBtn').click()
 def ready(p):p.locator('#readyBtn').click()
 def room(p):menu(p);p.locator('#returnRoomBtn').click();p.wait_for_function('["menu","onlineLobby"].includes(leqra.getState().phase)')
 def team(p,id,n):p.locator(f'#roomRoster [data-team="{id}"]').select_option(str(n));p.wait_for_function('([id,n])=>leqra.getState().room.players.find(p=>p.id===id)?.team===n',arg=[id,n]);p.wait_for_timeout(160)
 def start(p):p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=8000)
 def local_lane(p):
  p.evaluate('''()=>{const T=__test,w=leqra.getState().world;T.clearInput();T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.pickups.splice(0);T.tanks.forEach((t,i)=>Object.assign(t,{x:120,y:90+i*125,angle:0,invulnerable:100,cooldown:t.human?0:1000,power:null,powerTime:0,speedTime:0,charges:0,shield:0}));T.updateHUD(true);}''')
 def shells(p,id):return p.evaluate('id=>__test.bullets.filter(b=>b.owner===id).length',id)
 def save2(p,name,prefix='room'):
  form=p.locator('#'+prefix+'P2CallsignForm');form.locator('input').fill(name);form.locator('button').click();p.wait_for_function('name=>leqra.getState().room.players.some(p=>p.kind==="local"&&p.name===name)',arg=name)
 p=load('CAPTAIN')
 check(not p.locator('#roomP2CallsignForm').is_visible() and not p.locator('#pilotLoadout2').is_visible(),'Secondary name/HUD absent with only one local pilot')
 start(p);local_lane(p);press(p,'KeyF',45)
 check(shells(p,0)==1,'F fires primary tank in single-player room')
 check(p.evaluate('!document.fullscreenElement'),'F does not toggle fullscreen')
 local_lane(p);press(p,'Space',45);check(shells(p,0)==1,'Space remains fire alias with one local pilot')
 local_lane(p);p.evaluate("()=>{const t=__test.tanks[0];__test.grantPower(t,'grenade');t.charges=1;}")
 p.keyboard.down('KeyF');p.wait_for_timeout(60);check(shells(p,0)==1,'F throws one grenade')
 p.keyboard.down('Space');p.wait_for_timeout(80);check(shells(p,0)==1,'Holding F then pressing Space is not a second logical Fire press')
 p.keyboard.up('KeyF');p.wait_for_timeout(60);check(shells(p,0)==1,'Releasing F while Space is held does not detonate')
 p.keyboard.up('Space');press(p,'KeyF',40);check(shells(p,0)==0,'Fresh Fire press after both aliases are released detonates')
 room(p);p.locator('#addLocalBtn').click();waitplayers(p,4)
 lid=next(x['id'] for x in state(p)['room']['players'] if x['kind']=='local');check(lid==3,'Secondary player uses sparse slot 3, not assumed slot 1')
 check(p.locator('#roomP2CallsignForm').is_visible(),'Explicit Player 2 callsign editor appears on add')
 save2(p,'NOVA');check(p.locator('#roomP2CallsignStatus').inner_text()=='Saved.','Secondary local name save confirmed')
 check(p.evaluate('localStorage.getItem("leqra.local2Name")')=='NOVA','Secondary name remembered on device')
 p.locator('#roomP2Callsign').fill('   ');check(p.locator('#roomP2CallsignForm button').is_disabled(),'Empty Player 2 name is not saveable');p.locator('#roomP2Callsign').fill('NOVA')
 start(p);local_lane(p);check(p.locator('#pilotLoadout2').is_visible(),'Secondary ammo panel appears in play')
 check(p.locator('#loadoutName2').inner_text()=='NOVA' and p.locator('#loadoutKey1').inner_text()=='F','Both HUD identities and new P1 binding displayed')
 press(p,'Space',40);check(shells(p,0)==0 and shells(p,lid)==0,'Space does not fire either tank with two local pilots')
 p.keyboard.down('KeyF');p.keyboard.down('Enter');p.wait_for_timeout(75);p.keyboard.up('KeyF');p.keyboard.up('Enter');p.wait_for_timeout(100)
 check(shells(p,0)==1 and shells(p,lid)==1,'F and Enter fire independent local tanks simultaneously')
 check(p.locator('#ammoDots .ammo-dot.empty').count()==1 and p.locator('#ammoDots2 .ammo-dot.empty').count()==1,'Both ammo counters reflect their own active bullets')
 local_lane(p);p.evaluate('id=>{const t=__test.tanks.find(t=>t.id===id);__test.grantPower(t,"grenade");t.charges=1;}',lid)
 # A press/release entirely between simulation ticks must map to the actual sparse seat.
 p.evaluate("()=>{window.dispatchEvent(new KeyboardEvent('keydown',{code:'Enter',bubbles:true}));window.dispatchEvent(new KeyboardEvent('keyup',{code:'Enter',bubbles:true}));}")
 p.wait_for_timeout(100);check(shells(p,lid)==1,'Sub-tick Enter tap launches for secondary slot 3')
 p.wait_for_timeout(100);check('DETONATE' in p.locator('#weaponLabel2').inner_text(),'Secondary final-charge grenade keeps fuse/detonate display')
 check('DETONATE' not in p.locator('#weaponLabel').inner_text(),'Secondary grenade does not change primary weapon label')
 press(p,'Enter',45);p.wait_for_timeout(100);check(shells(p,lid)==0 and 'DETONATE' not in p.locator('#weaponLabel2').inner_text(),'Secondary manual detonation clears its own fuse HUD')
 menu(p);before=state(p);save2(p,'STAR FOX',prefix='menu');after=state(p)
 check(before['scores']==after['scores'] and before['round']==after['round'] and before['tanks'][0]['x']==after['tanks'][0]['x'],'In-match local P2 rename does not restart round or reset scores')
 check(p.locator('#loadoutName2').inner_text()=='STAR FOX','Renamed secondary appears in gameplay HUD')
 check(p.locator('#menuP2CallsignStatus').inner_text()=='Saved.','In-match name save confirmed')
 p.locator('#returnRoomBtn').click();p.wait_for_function('leqra.getState().phase==="menu"');remove(p,lid);p.locator('#addLocalBtn').click()
 check(next(x['name'] for x in state(p)['room']['players'] if x['kind']=='local')=='STAR FOX','Removing and re-adding secondary uses saved callsign')
 # Keep just two local humans, then publish and add a genuine remote human.
 remove(p,1);remove(p,2);code='Impact HUD '+str(int(time.time()))+' 💥';p.locator('#localRoomName').fill(code);p.locator('#copyInviteBtn').click();connected(p);waitplayers(p,2)
 lid=next(x['id'] for x in state(p)['room']['players'] if x['kind']=='local');guest=load('GUEST',code);connected(guest);waitplayers(p,3)
 check(not guest.locator('#roomP2CallsignForm').is_visible(),'Remote guest cannot edit a secondary pilot they do not control')
 ready(guest);p.wait_for_function('!document.querySelector("#startRoomBtn").disabled')
 save2(p,'ONLINE NOVA');guest.wait_for_function('leqra.getState().room.players.some(p=>p.name==="ONLINE NOVA")')
 check(next(x['ready'] for x in state(p)['room']['players'] if x['name']=='GUEST'),'Secondary rename preserves guest readiness online')
 start(p);guest.wait_for_function('leqra.getState().phase==="playing"');fixture(code,'powerups',player=0,power='rapid',missileScene='range');p.wait_for_timeout(200)
 press(p,'Space',40);p.wait_for_timeout(80);check(not latest(p)['bullets'],'Server receives no Fire from Space with a secondary local tank')
 p.keyboard.down('KeyF');p.keyboard.down('Enter');p.wait_for_timeout(80);p.keyboard.up('KeyF');p.keyboard.up('Enter');p.wait_for_timeout(180)
 check(any(b['owner']==0 for b in latest(p)['bullets']) and any(b['owner']==lid for b in latest(p)['bullets']),'Server receives both F and Enter controls independently')
 check(p.locator('#ammoDots2 .ammo-dot.empty').count()>=1 and not guest.locator('#pilotLoadout2').is_visible(),'Online controller sees P2 ammo; remote guest does not get an unrelated P2 HUD')
 fixture(code,'powerups',player=lid,power='grenade',charges=1,missileScene='range');p.wait_for_timeout(200);press(p,'Enter',40);p.wait_for_timeout(130)
 check('DETONATE' in p.locator('#weaponLabel2').inner_text(),'Server-backed secondary grenade displays armed HUD after final charge')
 press(p,'Enter',40);p.wait_for_timeout(180);check(not any(b['owner']==lid and b['kind']=='grenade' for b in latest(p)['bullets']),'Online P2 Enter remote detonation still works')
 menu(p);before=state(p);save2(p,'BATTLE NOVA','menu');guest.wait_for_function('leqra.getState().room.players.some(p=>p.name==="BATTLE NOVA")')
 check(before['scores']==state(p)['scores'] and before['round']==state(p)['round'],'Online in-match P2 rename preserves score and round')
 p.locator('#onlineReturnBtn').click();p.wait_for_timeout(150)
 # Real server-authoritative impact grenade trials; same path visible to guest.
 fixture(code,'powerups',player=0,power='grenade',missileScene='grenade-shield');p.wait_for_timeout(200);press(p,'KeyF',45)
 p.wait_for_function('(()=>{const s=__messages.filter(m=>m.type==="state").at(-1);return s.events.some(e=>e.type==="blast"&&e.generation===s.generation)})()',timeout=4000)
 ss=latest(p);enemy=next(t for t in ss['tanks'] if t['id']==2)
 check(enemy['alive'] and enemy['shield']==0,'Online grenade impact consumes one shield without a double-hit kill')
 check(ss['roundClock']>71,'Online impact detonates before five-second fuse')
 fixture(code,'powerups',player=0,power='grenade',missileScene='grenade-impact');p.wait_for_timeout(200);gen=latest(p)['generation'];press(p,'KeyF',45)
 p.wait_for_function('gen=>__messages.some(m=>m.type==="state"&&m.generation===gen&&m.tanks.some(t=>t.id===2&&!t.alive))',arg=gen,timeout=4000)
 check(True,'Unshielded opposing tank is eliminated on online grenade impact')
 guest.wait_for_function('gen=>__messages.some(m=>m.type==="state"&&m.generation===gen&&m.events.some(e=>e.type==="blast"))',arg=gen,timeout=4000)
 check(True,'Impact blast event reaches remote browser')
 p.screenshot(path=str(out/'online-impact.png'))
 p.close();guest.close()
 # Local impact rules independently exercise the shipped browser physics.
 local=load('PHYSICS');start(local);local_lane(local)
 for case in ['direct','shield','teammate','protected','wall','owner','stationary']:
  got=local.evaluate('''kind=>{const T=__test;T.setPhase('paused');T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{alive:i<2,human:true,team:i+1,x:i?190:40,y:210,invulnerable:0,shield:kind==='shield'&&i===1?10:0}));const p=T.tanks[1];if(kind==='teammate')p.team=1;if(kind==='protected')p.invulnerable=10;const before=document.querySelector('#combatLog').textContent;const b={kind:'grenade',owner:0,x:164,y:210,vx:205,vy:0,r:6,life:5,age:.3,dead:false,bounces:0,color:'#ffc46b',trail:[]};if(kind==='wall'){T.walls.push({x:170,y:0,w:8,h:600});b.x=155;}if(kind==='owner'){b.x=40;b.vx=0;}if(kind==='stationary'){b.x=180;b.vx=0;}T.addBullet(b);T.updateBullets(.1);if(kind==='wall')T.walls.pop();return{dead:b.dead,life:b.life,alive:p.alive,shield:p.shield,ownerAlive:T.tanks[0].alive,vx:b.vx}}''',case)
  if case=='wall':check(not got['dead'] and got['vx']<0 and got['alive'],'Local grenade reflects from wall before tank contact')
  elif case in ['teammate','protected']:check(got['dead'] and got['alive'],'Local contact blast respects '+case+' protection')
  elif case=='shield':check(got['dead'] and got['alive'] and got['shield']==0,'Local impact shield absorbs exactly one blast')
  elif case=='owner':check(got['dead'] and not got['ownerAlive'],'Local own grenade triggers after launch grace')
  else:check(got['dead'] and not got['alive'] and got['life']>4.8,'Local '+case+' grenade impact before fuse')
 local.close()
 # Small-screen naming and dual loadouts, with all power types/long names.
 for size in [(1365,950),(320,568),(390,844),(844,390)]:
  phone=load('CAPTAIN LONGNAME',size=size);phone.locator('#addLocalBtn').click();waitplayers(phone,4);save2(phone,'SECOND LONGNAME')
  phone.locator('#roomP2Callsign').scroll_into_view_if_needed();phone.screenshot(path=str(out/f'room-{size[0]}x{size[1]}.png'))
  check(phone.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),'Room naming has no horizontal overflow '+str(size))
  start(phone);local_lane(phone);phone.evaluate('''()=>{const p=__test.tanks.find(t=>t.id===3);__test.grantPower(p,'homing');__test.grantPower(p,'speed');__test.grantPower(p,'shield');__test.grantPower(__test.tanks[0],'scatter');__test.updateHUD(true);}''');phone.wait_for_timeout(100)
  check('HOMING' in phone.locator('#weaponLabel2').inner_text() and '×3' in phone.locator('#weaponLabel2').inner_text(),'Secondary weapon charges shown '+str(size))
  check('SPEED' in phone.locator('#buffLabel2').inner_text() and 'SHIELD' in phone.locator('#buffLabel2').inner_text(),'Secondary independent buff timers shown '+str(size))
  check(phone.evaluate('''()=>{const ids=['pilotLoadout1','pilotLoadout2','weaponLabel2','buffLabel2'];return ids.every(id=>{const b=document.getElementById(id).getBoundingClientRect();return b.left>=0&&b.right<=innerWidth+1&&b.top>=0&&b.bottom<=innerHeight+1})}'''),'Both loadouts fit viewport '+str(size))
  check(phone.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),'Playing HUD has no horizontal overflow '+str(size))
  for power,cap in [('rapid',9),('scatter',12),('laser',3),('grenade',3),('homing',3)]:
   phone.evaluate('power=>{__test.grantPower(__test.tanks.find(t=>t.id===3),power);__test.updateHUD(true)}',power)
   check(phone.locator('#ammoDots2 .ammo-dot').count()==cap,'Secondary '+power+' capacity '+str(size))
  phone.evaluate("()=>{__test.grantPower(__test.tanks.find(t=>t.id===3),'homing');__test.updateHUD(true)}");phone.screenshot(path=str(out/f'playing-{size[0]}x{size[1]}.png'))
  if size[0]<760 or size[1]<620:
   c=phone.context.new_cdp_session(phone);sb=phone.locator('#stickBase').bounding_box();fb=phone.locator('#fireBtn').bounding_box();points=[{'x':sb['x']+sb['width']/2+26,'y':sb['y']+sb['height']/2,'id':1},{'x':fb['x']+fb['width']/2,'y':fb['y']+fb['height']/2,'id':2}]
   c.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':points});phone.wait_for_timeout(150);c.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   check(shells(phone,0)>0,'Paired HUD leaves touch steering/fire usable '+str(size))
  phone.close()
 check(not errors,'No browser runtime errors: '+str(errors))
 report={'version':'3.1.0','assertions':len(checks),'checks':checks,'errors':errors,'limits':'Chromium exact shipped assets; synthetic Location/History/storage; real local Go WebSockets, no physical devices/public WAN.'}
 (out/'report.json').write_text(json.dumps(report,indent=2));browser.close();print('TOTAL',len(checks))

"""v3.1 regression of the unified-room exact-asset Chromium integration against opt-in loopback Go fixture.
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
def dismissVictory(p):
 if p.locator('#victoryDialog').count() and p.locator('#victoryDialog').is_visible():p.locator('#victoryCloseBtn').click()
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
 def menu(p):dismissVictory(p);p.locator('#roomBtn').click()
 def ready(p):dismissVictory(p);p.locator('#readyBtn').click()
 def room(p):menu(p);p.locator('#returnRoomBtn').click();p.wait_for_function('["menu","onlineLobby"].includes(leqra.getState().phase)')
 def team(p,id,n):p.locator(f'#roomRoster [data-team="{id}"]').select_option(str(n));p.wait_for_function('([id,n])=>leqra.getState().room.players.find(p=>p.id===id)?.team===n',arg=[id,n]);p.wait_for_timeout(160)
 def start(p):dismissVictory(p);p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=8000)
 # Offline room workflow through actual UI; no backend until Share.
 host=load('ADAM')
 check(state(host)['mode']=='room' and host.locator('#roomScreen').is_visible(),'Startup is a local game room, not a mode chooser')
 check(host.evaluate('__sockets.length')==0,'Local room and solo play need no WebSocket')
 check([p['kind'] for p in state(host)['room']['players']]==['human','bot','bot'],'Default roster is host plus two bots')
 host.locator('#roomCallsignForm input').fill('CAPTAIN');host.locator('#roomCallsignForm button').click();check(state(host)['room']['players'][0]['name']=='CAPTAIN','Callsign editable in local room')
 host.locator('[data-bot-difficulty="1"]').select_option('easy');host.locator('[data-bot-difficulty="2"]').select_option('hard')
 check([p.get('difficulty') for p in state(host)['room']['players'][1:]]==['easy','hard'],'Individual Chill and Fierce bot settings')
 host.locator('#addLocalBtn').click();waitplayers(host,4)
 check(state(host)['room']['players'][3]['kind']=='local','Second local player can use a nonadjacent roster slot')
 check(host.locator('#addBotBtn').is_disabled() and host.locator('#addLocalBtn').is_disabled(),'Four-seat cap enforced in local room')
 for id in (1,2):team(host,id,1)
 check(host.locator('#startRoomBtn').is_disabled(),'One-team local match cannot start')
 for id in (1,2):team(host,id,2)
 start(host)
 check(len(state(host)['tanks'])==4 and host.evaluate('__sockets.length')==0,'Four local participants play without server')
 # Controlled local lane: actual input paths with secondary slot3.
 host.evaluate('''()=>{const T=__test,w=leqra.getState().world;T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{x:100,y:90+i*130,angle:0,invulnerable:100,cooldown:99}));}''')
 host.keyboard.down('KeyW');host.keyboard.down('ArrowUp');host.wait_for_timeout(550);host.keyboard.up('KeyW');host.keyboard.up('ArrowUp')
 ts=state(host)['tanks'];check(ts[0]['x']>140 and ts[3]['x']>140,'Both local keyboard movement paths work simultaneously')
 check(abs(ts[0]['x']-ts[3]['x'])<6,'Both local human tanks use the same movement speed')
 # Local grenade final-charge and secondary control no crosstalk.
 host.evaluate('''()=>{__test.clearInput();__test.clearBullets();let t=__test.tanks.find(t=>t.id===3);t.cooldown=0;__test.grantPower(t,'grenade');t.charges=1;}''')
 press(host,'Space');host.wait_for_timeout(100)
 check(host.evaluate('__test.bullets.some(b=>b.owner===3&&b.kind==="grenade")'),'Second local player Space throws grenade')
 press(host,'Space');host.wait_for_timeout(80)
 check(host.evaluate('!__test.bullets.some(b=>b.owner===3&&b.kind==="grenade")'),'Second local player Space detonates final-charge grenade')
 room(host);check(state(host)['mode']=='room' and len(state(host)['room']['players'])==4,'Return to local room retains roster')
 # Remove + re-add using the last remaining bot difficulty.
 remove(host,2);inherited=next((x['difficulty'] for x in reversed(state(host)['room']['players']) if x['kind']=='bot'),'normal');host.locator('#addBotBtn').click();waitplayers(host,4)
 check(state(host)['room']['players'][2]['difficulty']==inherited,'Add Bot uses the last roster bot difficulty')
 remove(host,2) # one free seat for guest
 code='Team room '+str(int(time.time()))+' 💥 & +/#'
 host.locator('#localRoomName').fill(code);host.locator('#copyInviteBtn').click();connected(host);waitplayers(host,3)
 check([p['kind'] for p in state(host)['room']['players']]==['human','bot','local'],'Sharing imports the configured room rather than a replacement empty lobby')
 check(state(host)['room']['players'][1]['difficulty']=='easy' and state(host)['room']['players'][2]['team']==1,'Sharing preserves bot difficulty and local teammate')
 check(host.evaluate('new URL(__historyCalls.at(-1)).searchParams.get("room")')==code,'Shared room URL uses accepted arbitrary Unicode name')
 host.locator('#copyInviteBtn').click();check(host.evaluate('new URL(__copied).searchParams.get("room")')==code,'Copy Invite matches room URL')
 conflict=load('CONFLICT');conflict.locator('#localRoomName').fill(code);conflict.locator('#copyInviteBtn').click()
 conflict.wait_for_function('leqra.getState().mode==="room"&&document.querySelector("#roomStatus").textContent.includes("already in use")')
 check(len(state(conflict)['room']['players'])==3 and len(state(host)['room']['players'])==3,'Failed Share retains local roster and leaves existing online room untouched');conflict.close()
 guest=load('GUEST',code,(390,844));connected(guest);waitplayers(host,4)
 check(guest.locator('#roomScreen').is_visible() and not guest.locator('#joinDialog').is_visible(),'Invite joins directly into same unified room')
 gid=state(guest)['online']['id'];lid=next(p['id'] for p in state(host)['room']['players'] if p['kind']=='local')
 check(guest.locator('#rosterTools').is_hidden() and guest.locator('#startRoomBtn').is_hidden() and guest.locator('#roomRoster select').count()==0,'Guest sees roster but cannot configure or start it')
 team(host,gid,2);ready(guest);host.wait_for_function('!document.querySelector("#startRoomBtn").disabled')
 # Verify server rejection of forged guest team edits before start.
 guest.evaluate('''()=>{const p=leqra.getState().room.players[0];__sockets.at(-1).send(JSON.stringify({type:'configure',target:p.id,member:p.member,team:4}));}''')
 guest.wait_for_function('__messages.some(m=>m.type==="error"&&m.code==="not_host")');check(state(host)['room']['players'][0]['team']==1,'Server rejects guest-forged team change')
 start(host);guest.wait_for_function('leqra.getState().phase==="playing"');check(latest(host)['tanks'][1]['bot'] and latest(host)['tanks'][1]['difficulty']=='easy','Online bots are server-simulated participants with selected difficulty')
 fixture(code);host.wait_for_timeout(200)
 # Prevent fixture bot from shooting while isolating keyboard motion: enemy remains invulnerable locally visual only? use snapshot spawn lanes and short test, no need.
 before=latest(host);x0=before['tanks'][0]['x'];x2=next(t for t in before['tanks'] if t['id']==lid)['x']
 host.keyboard.down('KeyW');host.keyboard.down('ArrowUp');host.wait_for_timeout(650);host.keyboard.up('KeyW');host.keyboard.up('ArrowUp');host.wait_for_timeout(80)
 after=latest(host);dx0=after['tanks'][0]['x']-x0;dx2=next(t for t in after['tanks'] if t['id']==lid)['x']-x2
 check(dx0>60 and dx2>60,'Go server simulates both host keyboard pilots concurrently')
 check(abs(dx0-dx2)<9,'Online secondary input uses independent prediction and acknowledgement')
 check(host.evaluate('id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.forward)',lid),'Secondary input names owned seat explicitly')
 # Release primary without stopping secondary.
 x0=after['tanks'][0]['x'];x2=next(t for t in after['tanks'] if t['id']==lid)['x'];host.keyboard.down('ArrowUp');host.wait_for_timeout(380);host.keyboard.up('ArrowUp');host.wait_for_timeout(70);after=latest(host)
 check(abs(after['tanks'][0]['x']-x0)<9 and next(t for t in after['tanks'] if t['id']==lid)['x']-x2>35,'Secondary movement does not steer or move primary')
 # Real grant fixture exercises owned weapon control after sharing.
 fixture(code,'powerups',player=lid,power='grenade',missileScene='range');host.wait_for_timeout(250)
 press(host,'Space');host.wait_for_timeout(160)
 
 if not any(b['owner']==lid and b['kind']=='grenade' and b['life']>4.5 for b in latest(host)['bullets']):
  print('DEBUG_SECONDARY',lid,json.dumps(latest(host)),host.evaluate('__sent.slice(-24)'),state(host),flush=True)
 check(any(b['owner']==lid and b['kind']=='grenade' and b['life']>4.5 for b in latest(host)['bullets']),'Server gives secondary grenade a five-second fuse')
 press(host,'Space');host.wait_for_timeout(140)
 check(not any(b['owner']==lid and b['kind']=='grenade' for b in latest(host)['bullets']),'Owned secondary grenade remotely detonates online')
 guest.evaluate('id=>__sockets.at(-1).send(JSON.stringify({type:"input",player:id,seq:999,fire:true}))',lid);guest.wait_for_function('__messages.some(m=>m.type==="error"&&m.code==="not_owned")')
 check(True,'Other browser cannot control host secondary pilot')
 # Real disconnected owner and host handoff; restore local control, no bot/local host election.
 ownerid=state(host)['online']['id'];host.evaluate('__sockets.at(-1).close(4001,"test interruption")');guest.wait_for_function('leqra.getState().room.host===leqra.getState().online.id')
 host.wait_for_function('__messages.filter(m=>m.type==="welcome").length>=2&&leqra.getState().online.connected',timeout=12000)
 check(state(host)['online']['id']==ownerid and next(p for p in state(host)['room']['players'] if p['kind']=='local')['owner']==ownerid,'Reconnect restores both controlled seats after host handoff')
 check(state(guest)['room']['host']==gid and guest.locator('#roomBtn').is_visible(),'Host handoff chooses real online human, not bot or local P2')
 fixture(code);host.wait_for_timeout(300);x2=next(t for t in latest(host)['tanks'] if t['id']==lid)['x'];press(host,'ArrowUp',350);host.wait_for_timeout(100)
 check(next(t for t in latest(host)['tanks'] if t['id']==lid)['x']>x2+25,'Secondary movement resumes after reconnect and host handoff')
 menu(guest);guest.locator('#returnRoomBtn').click();guest.wait_for_function('leqra.getState().phase==="onlineLobby"');host.wait_for_function('leqra.getState().phase==="onlineLobby"')
 check(len(state(guest)['room']['players'])==4,'New host returns everyone to room without losing roster')
 # Kick primary owner removes secondary but preserves bot.
 guest.locator(f'#roomRoster [data-kick-target="{ownerid}"]').click();guest.locator('#confirmKickBtn').click();waitplayers(guest,2)
 check(not any(p['kind']=='local' for p in state(guest)['room']['players']),'Kick owner also removes dependent local seat')
 host.wait_for_function('leqra.getState().mode==="room"');check(host.locator('#joinDialog').is_visible(),'Kicked controller returns locally and sees removal notice')
 host.close();guest.close() # Completed clients need not render while mobile cases run.
 # All mobile layouts: unified room scroll retains reachable controls.
 for size in [(320,568),(390,844),(844,390)]:
  p=load('PHONE',size=size);p.locator('#addLocalBtn').click();waitplayers(p,4)
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),'No horizontal overflow '+str(size))
  p.locator('#startRoomBtn').scroll_into_view_if_needed();box=p.locator('#startRoomBtn').bounding_box()
  check(box is not None and box['y']>=0 and box['y']+box['height']<=size[1]+1,'Start button reachable '+str(size))
  p.screenshot(path=str(out/f'room-{size[0]}x{size[1]}.png'))
  dismissVictory(p);p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"');check(p.locator('#touchControls').is_visible(),'Mobile touch controls restored during match '+str(size))
  # actual simultaneous CDP touch steering+fire on controlled invulnerable arena
  p.evaluate('''()=>{__test.tanks.forEach(t=>t.invulnerable=100);__test.tanks[0].cooldown=0;}''');p.wait_for_timeout(150)
  client=p.context.new_cdp_session(p);sb=p.locator('#stickBase').bounding_box();fb=p.locator('#fireBtn').bounding_box();sx=sb['x']+sb['width']/2+27;sy=sb['y']+sb['height']/2;fx=fb['x']+fb['width']/2;fy=fb['y']+fb['height']/2
  client.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':sx,'y':sy,'id':1},{'x':fx,'y':fy,'id':2}]})
  # Wait for a simulation frame rather than assuming the software renderer runs
  # within 220 ms while several emulated devices are active.
  p.wait_for_function('__test.bullets.some(b=>b.owner===0)',timeout=3000)
  check(p.evaluate('document.querySelector("#stickKnob").style.transform!=="translate(0,0)"'),'Simultaneous mobile steering and Fire '+str(size))
  client.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
  p.screenshot(path=str(out/f'playing-{size[0]}x{size[1]}.png'));p.close()
 # Four independent online human controllers use the same unified room.
 fourhost=load('FOUR HOST');fourhost.locator('#joinOtherBtn').click();fourhost.locator('#createRoomBtn').click();connected(fourhost)
 code4=state(fourhost)['online']['code'];four=[fourhost]+[load('PILOT '+str(i),code4,(390,844) if i==1 else (1365,950)) for i in range(1,4)]
 for p in four:connected(p);waitplayers(p,4)
 for id in range(4):team(fourhost,id,1+id%2)
 for p in four[1:]:ready(p)
 fourhost.wait_for_function('!document.querySelector("#startRoomBtn").disabled');start(fourhost)
 for p in four:p.wait_for_function('leqra.getState().phase==="playing"')
 for i,p in enumerate(four):check(state(p)['online']['id']==i and len(state(p)['tanks'])==4,'Four-browser team match: distinct controller '+str(i))
 fixture(code4,'powerups',power='laser',player=0);fourhost.wait_for_timeout(180);press(fourhost,'Space',50)
 for i,p in enumerate(four):
  p.wait_for_function('__messages.some(m=>m.type==="state"&&(m.events||[]).some(e=>e.type==="laser"))')
  check(True,'Laser beam event reaches online team client '+str(i))
 for p in four:p.close()
 # Sparse seat IDs after removal must not be mistaken for array indices.
 sparse=load('SPARSE');remove(sparse,1);start(sparse)
 sparse.evaluate("()=>{const t=__test.tanks.find(t=>t.id===0);t.invulnerable=0;__test.hurt(t,{owner:2,kind:'normal'});}")
 check(not next(t for t in state(sparse)['tanks'] if t['id']==0)['alive'],'Removed roster slot does not break elimination by higher-ID bot')
 sparse.close()
 # Same power icon geometry at both pixel densities; Go/JS missile parity after intentional retune.
 icons=load('ICONS')
 rows=icons.evaluate(r'''()=>{const result=[];for(const icon of document.querySelectorAll('canvas[data-power-icon]')){const copy=document.createElement('canvas');copy.width=copy.height=icon.width;const c=copy.getContext('2d');c.setTransform(copy.width/26,0,0,copy.width/26,copy.width/2,copy.height/2);__test.powerIcon(icon.dataset.powerIcon,c);const a=c.getImageData(0,0,copy.width,copy.height).data,b=icon.getContext('2d').getImageData(0,0,icon.width,icon.height).data;if(!a.some(v=>v>0)||!a.every((v,i)=>v===b[i]))throw Error('icon mismatch '+icon.dataset.powerIcon);result.push(icon.dataset.powerIcon)}return result}''')
 for kind in rows:check(True,'Exact legend/maze icon pixels: '+kind)
 for case in json.loads((root/'tests/missile-fixtures.json').read_text()):
  got=icons.evaluate(r'''c=>{const T=__test;T.setMode('duel');T.resetPreview();T.setPhase('playing');T.clearBullets();T.setWorld(c.world);T.tanks.forEach((t,i)=>Object.assign(t,c.tanks[i]));const b={...c.bullet,dead:false,trail:[]};T.addBullet(b);for(let i=0;i<c.steps;i++){if(c.moveY)T.moveTank(T.tanks[1],0,c.moveY/60);T.updateBullets(1/60)}T.setPhase('menu');return{bullet:b,alive:T.tanks[1].alive}}''',case)
  for field in ['x','y','vx','vy','life','age','rangeLeft','seekDelay','bounces','target']:
   check(abs(got['bullet'].get(field,0)-case['expected'].get(field,0))<1e-6,'Go/JS aggressive missile parity '+case['name']+' '+field)
  check(got['alive']==case['alive'],'Go/JS missile hit parity '+case['name'])
 icons.evaluate('__test.createLocalRoom()');icons.screenshot(path=str(out/'desktop-room.png'))
 check(not errors,'No browser runtime errors: '+str(errors))
 report={'version':'3.2.0','assertions':len(checks),'checks':checks,'errors':errors,'limits':'Chromium exact asset injection; synthetic Location/History/storage; real loopback Go sockets; no physical devices or public internet.'}
 (out/'report.json').write_text(json.dumps(report,indent=2));browser.close();print('TOTAL',len(checks))

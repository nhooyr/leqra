"""v2.7 ricochet / remote grenade shipped-client checks. Run TestBrowserFixture, then this script.
The restricted browser cannot navigate to local pages. Assets, storage, location
and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
History calls and encoded invite contents are checked, not real browser navigation.
"""
import argparse,json,re,secrets
from pathlib import Path
from urllib.parse import urlencode,urlsplit,parse_qs
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('url',nargs='?',default='http://127.0.0.1:8790');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/weapons-v27');args=ap.parse_args()
root=Path(__file__).resolve().parents[1]/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(v,label):
 assert v,label
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def fixture(code,power='',player=0,speed=False,shield=False,cover=False):
 req=Request(args.url+'/_fixture/powerups',data=json.dumps(dict(code=code,power=power,player=player,speed=speed,shield=shield,cover=cover)).encode(),headers={'Content-Type':'application/json'})
 with urlopen(req,timeout=5) as res:return json.load(res)

with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[]
 def load(name='PILOT',code=None,size=(1365,950),session=None,history_throws=False):
  mobile=size[0]<760 or size[1]<620
  context=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1)
  contexts.append(context);p=context.new_page();p.on('pageerror',lambda e:errors.append(str(e)))
  # A synthetic reachable public URL exercises the normal Copy Invite path.
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code}) if code is not None else '')
  ws=args.url.replace('http:','ws:').replace('https:','wss:')+'/ws'
  html=re.sub(r'<link[^>]*>','',root.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+root.joinpath('style.css').read_text()+'</style></head>')
  p.set_content(html)
  p.evaluate(r'''([url,ws,name,session,historyThrows])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied='';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;window.WebSocket=class extends RealSocket{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,'localStorage',{value:store({'leqra.name':name,'leqra.muted':'1'})});
   Object.defineProperty(window,'sessionStorage',{value:store(session?{'leqra.session':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{if(historyThrows)throw Error('Restricted History');__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{__copied=v}}});
  }''',[url,ws,name,session,history_throws])
  js=root.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);pos=js.rfind('})();');js=js[:pos]+'})(window.__location);'+js[pos+5:]
  p.add_script_tag(content=root.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def connected(p):p.wait_for_function('leqra.getState().online?.connected',timeout=10000)


 offline=load('OFFLINE')
 result=offline.evaluate(r"""()=>{
  const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
  const setup=(mode='solo')=>{
   T.setMode(mode);T.resetPreview();T.clearBullets();T.setPhase('playing');
   const w=leqra.getState().world;
   T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
   T.tanks.forEach((t,i)=>Object.assign(t,{x:i?600+i*100:120,y:i?550:100,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0,fireHeld:false,fireBlocked:false}));
   return T.tanks;
  };
  const tap=code=>{window.dispatchEvent(new KeyboardEvent('keydown',{code}));window.dispatchEvent(new KeyboardEvent('keyup',{code}));};
  const length=ps=>ps.reduce((v,p,i)=>v+(i?Math.hypot(p.x-ps[i-1].x,p.y-ps[i-1].y):0),0);
  let ts=setup(),w=leqra.getState().world;ts[1].x=220;ts[1].y=300;ts[0].angle=Math.atan2(200,2*(w.width-7)-220-120);
  T.grantPower(ts[0],'laser');let beam=T.laserTrace(ts[0]);
  ok(beam.points.length===3&&beam.target===ts[1]&&beam.bounces===1,'Offline laser acquires tank after reflection');
  T.fire(ts[0]);ok(!ts[1].alive&&ts[0].alive,'Banked laser kills opponent and retains shooter immunity');
  ok(T.traces.at(-1).points.length===3,'Offline rendered beam preserves complete ricochet polyline');
  ts=setup();for(const t of ts.slice(1))t.alive=false;
  for(const angle of [0,.17,Math.PI/4,Math.PI/2,2.9]){ts[0].angle=angle;beam=T.laserTrace(ts[0]);ok(Math.abs(length(beam.points)-(2*(w.width+w.height)-28))<.00001,'Whole laser path uses one perimeter budget: '+angle);}
  ts=setup();ts[0].x=129;T.walls.push({x:150,y:0,w:8,h:w.height});beam=T.laserTrace(ts[0]);
  ok(beam.points[1].x===147&&beam.points.slice(1).every(p=>p.x<=147.00001),'Barrel against wall reflects without clipping through it');
  ts=setup();ts[0].x=220;ts[0].y=300;ts[1].x=120;ts[1].y=100;ts[1].angle=Math.atan2(200,2*(w.width-7)-220-120);
  ts[2].x=ts[1].x+100;ts[2].y=ts[1].y+100*Math.tan(ts[1].angle);ts[2].shield=10;T.grantPower(ts[1],'laser');T.fire(ts[1]);
  ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[2].shield===10,'Reflected bot laser passes through allies and their shields');

  ts=setup();T.grantPower(ts[0],'grenade');T.weaponControl(ts[0],true,true);let b=T.ownedGrenades(ts[0])[0];
  ok(b&&b.life===5&&ts[0].charges===2,'Offline grenade launches with exactly five-second fuse');
  b.x=400;b.y=100;b.vx=b.vy=0;
  for(let i=0;i<120;i++){ts[0].cooldown=0;T.weaponControl(ts[0],true,false)}
  ok(!b.dead&&T.ownedGrenades(ts[0]).length===1&&ts[0].charges===2,'Holding Fire neither detonates nor repeats a grenade');
  T.updateHUD(true);ok(document.getElementById('fireLabel').textContent==='BOOM'&&document.getElementById('weaponLabel').textContent.startsWith('DETONATE'),'Armed grenade switches Fire and HUD to detonation');
  T.weaponControl(ts[0],false,false);T.weaponControl(ts[0],true,true);
  ok(b.dead&&ts[0].charges===2,'Second press detonates without consuming a charge');
  for(let i=0;i<120;i++){ts[0].cooldown=0;T.weaponControl(ts[0],true,false)}
  ok(T.bullets.length===1,'Holding detonation does not also throw/shoot');
  T.weaponControl(ts[0],false,false);T.weaponControl(ts[0],true,true);
  ok(T.ownedGrenades(ts[0]).length===1&&ts[0].charges===1,'Release and press permits the next grenade');

  ts=setup();T.grantPower(ts[0],'grenade');ts[0].charges=1;tap('Space');T.humanControl(ts[0],1/120);b=T.ownedGrenades(ts[0])[0];
  ok(b&&!ts[0].power,'Sub-tick keyboard tap launches the final grenade');
  b.x=400;b.y=100;b.vx=b.vy=0;T.updateHUD(true);ok(document.getElementById('fireLabel').textContent==='BOOM','Final grenade retains detonation UI after weapon expiry');
  tap('Space');T.humanControl(ts[0],1/120);ok(b.dead&&T.bullets.length===1,'Sub-tick second tap detonates final grenade, not standard shot');

  ts=setup();T.grantPower(ts[0],'grenade');T.weaponControl(ts[0],true,true);b=T.ownedGrenades(ts[0])[0];b.x=400;b.y=100;b.vx=b.vy=0;T.clearInput();
  window.dispatchEvent(new KeyboardEvent('keydown',{code:'Space',repeat:true}));T.humanControl(ts[0],1/120);
  ok(!b.dead,'OS key repeat after focus/input reset cannot synthesize a fresh detonation');

  ts=setup('duel');T.grantPower(ts[1],'grenade');tap('Enter');T.humanControl(ts[1],1/120);b=T.ownedGrenades(ts[1])[0];
  ok(!!b,'Local second player uses Enter to throw');b.x=400;b.y=100;b.vx=b.vy=0;
  tap('Space');T.humanControl(ts[0],1/120);ok(!b.dead,'Player one cannot trigger player two grenade');
  tap('Enter');T.humanControl(ts[1],1/120);ok(b.dead,'Local second player uses Enter again to detonate');

  ts=setup();T.grantPower(ts[0],'grenade');T.fire(ts[0]);b=T.bullets[0];b.x=400;b.y=100;b.vx=b.vy=0;
  for(let i=0;i<599;i++)T.updateBullets(1/120);ok(!b.dead,'Grenade stays live until immediately before five seconds');
  T.updateBullets(1/120);ok(b.dead&&T.bullets.length===0,'Grenade automatically explodes at five seconds');

  ts=setup();T.grantPower(ts[1],'grenade');T.fire(ts[1]);b=T.ownedGrenades(ts[1])[0];b.x=ts[0].x+30;b.y=ts[0].y;b.vx=b.vy=0;ts[1].ai.think=0;
  T.botControl(ts[1],1/120);ok(b.dead&&!ts[0].alive&&ts[1].alive&&ts[2].alive,'Bots use early detonation only against the player');
  T.setPhase('menu');T.resetPreview();return passed;
 }""")
 for label in result:check(True,label)
 offline.close()

 host=load('HOST');host.locator('[data-mode=online]').click()
 check('Leave blank' not in host.locator('#netStatus').inner_text() and 'random room' not in host.locator('#netStatus').inner_text(),'Random-room hint is removed from online screen')
 code='leqra + boom 💥 '+secrets.token_hex(3);host.locator('#joinCode').fill(code);host.locator('#createRoomBtn').click();connected(host)
 check(host.evaluate('new URL(__location.href).searchParams.get("room")')==code,'Creating custom room still updates invite URL')
 phone=load('PHONE',code,(390,844));tiny=load('TINY',code,(320,568));wide=load('WIDE',code,(844,390));pages=[host,phone,tiny,wide]
 for p in pages:
  connected(p);p.wait_for_function('leqra.getState().online.players.length===4');p.locator('#readyBtn').click()
 host.locator('#startRoomBtn').click()
 for p in pages:p.wait_for_function('leqra.getState().phase==="playing"')
 def scenario(power,player=0,cover=False,speed=False,shield=False,charges=None):
  body=dict(code=code,power=power,player=player,cover=cover,speed=speed,shield=shield)
  if charges is not None:body['charges']=charges
  with urlopen(Request(args.url+'/_fixture/powerups',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'}),timeout=5) as res:data=json.load(res)
  for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g)',arg=data['generation']);p.wait_for_timeout(50)
  return data['generation']
 def events(p,gen,kind):return p.evaluate('([g,k])=>{const all=__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.events||[]).filter(e=>e.type===k&&e.generation===g);return [...new Map(all.map(e=>[e.id,e])).values()]}',[gen,kind])
 def tank(p,id):return next(t for t in state(p)['tanks'] if t['id']==id)
 def press(p,ms=70):p.keyboard.down('Space');p.wait_for_timeout(ms);p.keyboard.up('Space')

 gen=scenario('laser',player=2)
 tiny.keyboard.down('Space');tiny.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',arg=gen);tiny.keyboard.up('Space')
 tiny.screenshot(path=str(out/'ricochet-laser-320x568.png'))
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',arg=gen)
 beams=[events(p,gen,'laser')[0] for p in pages]
 check(all(e['points']==beams[0]['points'] for e in beams),'Four online clients receive identical full ricochet path')
 check(len(beams[0]['points'])>=3,'Server online laser has at least one reflected segment')
 tiny.wait_for_function('!leqra.getState().tanks.find(t=>t.id===1).alive')
 check(tank(tiny,2)['alive'] and tank(tiny,2)['charges']==2,'Online reflected hit consumes one charge without self-damage')

 gen=scenario('laser',cover=True);press(host)
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',arg=gen)
 e=events(host,gen,'laser')[0];pts=e['points'];length=sum(((b['x']-a['x'])**2+(b['y']-a['y'])**2)**.5 for a,b in zip(pts,pts[1:]))
 check(len(pts)>4 and abs(length-(2*(1008+672)-28))<.00001,'Online many-bounce miss is capped by total maze perimeter')
 check(tank(host,1)['alive'] and max(p['x'] for p in pts)<=327.00001,'Online laser reflects at cover rather than tunneling')
 host.screenshot(path=str(out/'laser-path-desktop.png'))

 gen=scenario('grenade');host.keyboard.down('Space');host.wait_for_timeout(1200)
 latest=host.evaluate('g=>__messages.filter(m=>m.type==="state"&&m.generation===g).at(-1)',gen)
 check(len([b for b in latest['bullets'] if b.get('kind')=='grenade'])==1 and tank(host,0)['charges']==2 and not events(host,gen,'blast'),'Online held Fire launches exactly one grenade, without detonation')
 check('DETONATE' in host.locator('#weaponLabel').inner_text(),'Online HUD advertises early detonation and countdown')
 host.keyboard.up('Space');press(host,1000)
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',arg=gen)
 check(len(events(host,gen,'blast'))==1 and tank(host,0)['charges']==2,'Fresh online press detonates once; holding does not throw another')
 host.wait_for_function('!leqra.getState().tanks.find(t=>t.id===1).alive')
 check(tank(host,0)['alive'],'Early grenade blast kills nearby enemy while distant owner survives')

 gen=scenario('grenade',charges=1);press(host)
 host.wait_for_function('!leqra.getState().tanks.find(t=>t.id===0).power&&document.getElementById("fireLabel").textContent==="BOOM"')
 check(True,'Online final-charge grenade stays remotely detonatable')
 host.wait_for_timeout(1000);press(host,400)
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',arg=gen)
 check(state(host)['bulletCount']==0,'Detonating the final grenade does not also fire a standard shell')

 gen=scenario('grenade');press(host);host.wait_for_timeout(2700)
 check(not events(host,gen,'blast'),'Untriggered online grenade remains live beyond old 1.6-second fuse')
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',arg=gen,timeout=6000)
 check(len(events(host,gen,'blast'))==1,'Five-second automatic fallback explodes exactly once on all clients')

 # Real Chromium multi-touch: steer and hold to throw, release, tap to detonate.
 gen=scenario('grenade',player=2,speed=True,shield=True)
 cdp=tiny.context.new_cdp_session(tiny);rect=tiny.locator('#fireBtn').bounding_box();st=tiny.locator('#stickBase').bounding_box()
 fire={'x':rect['x']+rect['width']/2,'y':rect['y']+rect['height']/2,'id':12};steer={'x':st['x']+st['width']/2-20,'y':st['y']+st['height']/2,'id':11}
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[steer,fire]});tiny.wait_for_timeout(400)
 tiny.wait_for_function('document.getElementById("fireLabel").textContent==="BOOM"')
 check(tiny.locator('#fireBtn').get_attribute('aria-label')=='Press to detonate your grenade','Mobile Fire button shows accessible detonation action')
 check(tiny.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Armed grenade controls fit compact phone without horizontal overflow')
 tiny.screenshot(path=str(out/'grenade-armed-320x568.png'))
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});tiny.wait_for_timeout(100)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[fire]});tiny.wait_for_timeout(70);cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 tiny.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.owner===2&&e.generation===g))',arg=gen)
 check(True,'Second mobile tap triggers server-authoritative detonation while steering remains supported')

 # Real client gesture using original gameplay handlers, full phone layout.
 for p,size in [(phone,(390,844)),(wide,(844,390))]:
  gen=scenario('grenade',player=state(p)['online']['id'],shield=True);press(p);p.wait_for_timeout(100)
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No overflow in armed grenade layout '+str(size))
  p.screenshot(path=str(out/f'grenade-{size[0]}x{size[1]}.png'))
 check(not errors,'No browser JavaScript errors')
 browser.close()
(out/'results.json').write_text(json.dumps({'checks_passed':len(checks),'checks':checks,'errors':errors,'limitations':'Chromium emulation; synthetic location/History/storage, exact shipped assets and live Go fixture sockets. Not real navigation, physical phones or public hosting.'},indent=2,ensure_ascii=False))
print('PASSED',len(checks),flush=True)

"""v2.5 actual-client power-up checks against the opt-in, loopback-only fixture.
LEQRA_BROWSER_FIXTURE=1 go test -run '^TestBrowserFixture$' -timeout 30m
python tests/powerups_browser.py http://127.0.0.1:8790 --isolated
The production app has no power-grant or test-map HTTP endpoints.
"""
import argparse,json,re,time
from pathlib import Path
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument('url',nargs='?',default='http://127.0.0.1:8790')
parser.add_argument('--isolated',action='store_true')
parser.add_argument('--browser',default=None)
parser.add_argument('--output',default='test-output/powerups')
a=parser.parse_args();root=Path(__file__).resolve().parents[1]/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def call(code,power='',player=0,speed=False,shield=False,cover=False):
 req=Request(a.url+'/_fixture/powerups',data=json.dumps(dict(code=code,power=power,player=player,speed=speed,shield=shield,cover=cover)).encode(),headers={'Content-Type':'application/json'})
 with urlopen(req,timeout=5) as res:return json.load(res)

with sync_playwright() as pw:
 opts={'headless':True}
 if a.browser:opts['executable_path']=a.browser
 browser=pw.chromium.launch(**opts)
 contexts=[]
 def load(name='PILOT',code='',size=(1365,950)):
  mobile=size[0]<760 or size[1]<620
  context=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1)
  contexts.append(context);p=context.new_page();p.on('pageerror',lambda e:errors.append(str(e)))
  url=a.url+'/?test=1'+('&room='+code if code else '')
  setup=r'''window.__sockets=[];window.__messages=[];
const RealSocket=WebSocket;window.WebSocket=class extends RealSocket{constructor(...a){super(...a);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}};
'''
  if a.isolated:
   setup+='''function store(data){return {getItem:k=>data[k]??null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
Object.defineProperty(window,'localStorage',{value:store({'leqra.name':NAME,'leqra.muted':'1'})});Object.defineProperty(window,'sessionStorage',{value:store({})});'''.replace('NAME',json.dumps(name))
   html=re.sub(r'<link[^>]*>','',root.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+root.joinpath('style.css').read_text()+'</style></head>')
   p.set_content(html);p.evaluate('()=>{'+setup+'}')
   js=root.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);pos=js.rfind('})();');js=js[:pos]+f'}})(new URL({json.dumps(url)}));'+js[pos+5:]
   p.add_script_tag(content=root.joinpath('netcode.js').read_text());p.add_script_tag(content=js)
  else:
   p.add_init_script(setup+f'localStorage.setItem("leqra.name",{json.dumps(name)});localStorage.setItem("leqra.muted","1");');p.goto(url)
  p.wait_for_function('window.leqra');return p,context

 # Synchronously exercise the actual offline game functions between RAF frames.
 offline,_=load('OFFLINE')
 result=offline.evaluate(r'''()=>{
 const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
 const setup=()=>{T.setMode('solo');T.resetPreview();T.setPhase('playing');T.clearBullets();const w=leqra.getState().world;
  T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
  T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0}));return T.tanks;
 };
 let ts=setup();T.grantPower(ts[0],'homing');T.grantPower(ts[0],'speed');T.grantPower(ts[0],'shield');ok(ts[0].power==='homing'&&ts[0].charges===3&&ts[0].speedTime===10&&ts[0].shield===10,'Offline independent weapon, speed and shield');
 for(const kind of ['homing','grenade']){ts=setup();T.grantPower(ts[0],kind);for(let i=0;i<3;i++){ts[0].cooldown=0;ok(T.fire(ts[0]),'Offline '+kind+' charge '+(i+1));}ok(!ts[0].power&&T.bullets.filter(b=>b.kind===kind).length===3,'Offline '+kind+' depletes after three shots');}
 ts=setup();ts[0].x=400;ts[0].y=280;ts[1].x=100;ts[1].y=210;ts[2].x=180;
 const missile={kind:'homing',owner:1,target:-1,x:135,y:210,vx:235,vy:0,r:5,age:.2,life:4.8};T.steerMissile(missile,1/60);ok(missile.target===0&&missile.vy>0,'Bot missile locks only the human, never its closer ally');
 ts=setup();ts[0].x=150;ts[1].x=170;ts[2].x=190;ts[1].shield=10;ts[2].shield=10;
 T.detonate({kind:'grenade',owner:1,x:170,y:210,color:ts[1].color,dead:false});ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[1].shield===10&&ts[2].shield===10,'Bot grenade cannot kill bots or consume their shields');
 ts=setup();ts[0].x=100;ts[1].x=150;T.detonate({kind:'grenade',owner:0,x:130,y:210,color:ts[0].color,dead:false});ok(!ts[0].alive&&!ts[1].alive,'Player grenade hurts the owner and enemy together');
 ts=setup();ts[0].x=120;ts[1].x=280;T.walls.push({x:248,y:0,w:8,h:500});T.detonate({kind:'grenade',owner:0,x:225,y:210,color:ts[0].color,dead:false});ok(!ts[0].alive&&ts[1].alive,'Offline grenade damage blocked by solid wall');
 ts=setup();ts[1].x=190;T.grantPower(ts[0],'grenade');T.fire(ts[0]);for(let i=0;i<48;i++)T.updateBullets(1/120);ok(ts[1].alive&&T.bullets.length===1,'Offline grenade rolls past tanks without contact detonation');
 const predicted=T.grenadeForecast(T.bullets[0]);ts[1].x=predicted.x;ts[1].y=predicted.y;for(let i=0;i<553;i++)T.updateBullets(1/120);ok(T.bullets.length===0&&!ts[1].alive,'Offline grenade fuse detonates and eliminates nearby enemy');
 ts=setup();T.grantPower(ts[0],'speed');const x=ts[0].x;window.dispatchEvent(new KeyboardEvent('keydown',{code:'KeyW'}));T.humanControl(ts[0],1/60);window.dispatchEvent(new KeyboardEvent('keyup',{code:'KeyW'}));ok(Math.abs(ts[0].x-x-128*1.65/60)<1e-6,'Offline super speed uses boosted keyboard movement');
 ts=setup();T.grantPower(ts[1],'homing');ts[0].x=400;ts[1].x=120;ts[1].angle=0;ok(!!T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0),'Bot recognizes a homing firing opportunity');ok(!T.evaluateBotShot(ts[1],0,ts[2],{lead:1},0),'Bot refuses an allied firing target');
 ts=setup();T.grantPower(ts[1],'grenade');ts[1].x=100;ts[0].x=380;ok(!!T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0),'Bot evaluates grenade landing point and blast');
 T.setPhase('menu');T.resetPreview();return passed;
 }''')
 for item in result:check(True,item)
 offline.close()

 # Real independent sockets, server-owned shots, and synchronized mobile visuals.
 host,hc=load('HOST');host.locator('[data-mode=online]').click();host.locator('#createRoomBtn').click();host.wait_for_function('leqra.getState().online?.connected');code=state(host)['online']['code']
 phone,pc=load('PHONE',code,(390,844));tiny,tc=load('POCKET',code,(320,568));wide,wc=load('WIDE',code,(844,390))
 pages=[host,phone,tiny,wide]
 for p in pages:p.wait_for_function('leqra.getState().online?.players.length===4');p.locator('#readyBtn').click()
 host.locator('#startRoomBtn').click()
 for p in pages:p.wait_for_function('leqra.getState().phase==="playing"')
 def scenario(power='',player=0,speed=False,shield=False,cover=False):
  data=call(code,power,player,speed,shield,cover)
  for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g)',arg=data['generation']);p.wait_for_timeout(100)
  return data['generation']
 gen=scenario('homing',speed=True,shield=True)
 for p in pages:p.wait_for_function('leqra.getState().tanks.find(t=>t.id===0)?.power==="homing"')
 check(all(next(t for t in state(p)['tanks'] if t['id']==0)['speedTime']>0 for p in pages),'All four clients receive concurrent missile and speed state')
 check('HOMING' in host.locator('#weaponLabel').inner_text() and '×3' in host.locator('#weaponLabel').inner_text(),'HUD displays equipped missiles and remaining charges')
 check('SPEED' in host.locator('#buffLabel').inner_text() and 'SHIELD' in host.locator('#buffLabel').inner_text(),'HUD shows independent speed and shield timers')
 host.keyboard.down('Space');host.wait_for_timeout(80);host.keyboard.up('Space')
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"))',arg=gen)
 check(True,'Homing missile is server-created and broadcast to all four clients')
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.target===1&&b.vy>1))',arg=gen)
 check(True,'Live missile changes direction and locks an opponent on the server')
 host.screenshot(path=str(out/'homing-desktop.png'))
 host.wait_for_function('leqra.getState().tanks.find(t=>t.id===1)?.alive===false',timeout=6000)
 check(True,'Live homing hit is confirmed by server damage')
 gen=scenario('grenade')
 host.keyboard.down('Space');host.wait_for_timeout(80);host.keyboard.up('Space')
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="grenade"&&b.life<4.7))',arg=gen)
 check(next(t for t in state(host)['tanks'] if t['id']==1)['alive'],'Live grenade does not cause immediate contact damage')
 host.screenshot(path=str(out/'grenade-fuse-desktop.png'))
 host.wait_for_timeout(1350);host.keyboard.down('Space');host.wait_for_timeout(60);host.keyboard.up('Space')
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.radius===110))',arg=gen)
 check(True,'All clients receive authoritative owner-triggered blast event')
 host.wait_for_function('leqra.getState().tanks.find(t=>t.id===1)?.alive===false')
 check(next(t for t in state(host)['tanks'] if t['id']==0)['alive'],'Thrower outside blast survives while nearby enemy is eliminated')
 # Real simultaneous touch while boosted and holding missiles.
 gen=scenario('homing',player=1,speed=True,shield=True)
 phone.wait_for_function('leqra.getState().tanks.find(t=>t.id===1)?.speedTime>0')
 before=next(t for t in state(phone)['tanks'] if t['id']==1)
 cdp=pc.new_cdp_session(phone);st=phone.locator('#stickBase').bounding_box();fb=phone.locator('#fireBtn').bounding_box()
 points=[{'x':st['x']+st['width']/2+35,'y':st['y']+st['height']/2,'id':11},{'x':fb['x']+fb['width']/2,'y':fb['y']+fb['height']/2,'id':12}]
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':points});phone.wait_for_timeout(360)
 after=next(t for t in state(phone)['tanks'] if t['id']==1)
 check(after['x']-before['x']>45,'Boosted mobile tank moves while firing missiles')
 check(phone.locator('#fireBtn').evaluate('e=>e.classList.contains("held")'),'Mobile fire remains held with active joystick')
 check(phone.evaluate('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.owner===1))',gen),'Touch Fire creates a server-owned missile')
 phone.screenshot(path=str(out/'mobile-speed-missile.png'))
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 phone.wait_for_timeout(70);check(not phone.locator('#fireBtn').evaluate('e=>e.classList.contains("held")'),'Touch release stops held fire')
 # Both compact layouts show all simultaneous timers without overlapping controls.
 for p,id,size in [(tiny,2,'320x568'),(wide,3,'844x390')]:
  scenario('grenade',player=id,speed=True,shield=True);p.wait_for_timeout(200)
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No horizontal overflow with full loadout: '+size)
  box=p.locator('#weaponLabel').bounding_box();buff=p.locator('#buffLabel').bounding_box();bar=p.locator('.underbar').bounding_box();stats=p.locator('#bestInline').bounding_box()
  check(box['x']+box['width']<=stats['x'] and buff['x']+buff['width']<=stats['x'] and buff['y']+buff['height']<=bar['y']+bar['height'],'Weapon, buffs and latency fit without overlap: '+size)
  p.screenshot(path=str(out/('full-loadout-'+size+'.png')))
 # Boost survives reconnect, without inventing or resetting its remaining time.
 scenario('grenade',player=0,speed=True)
 oldcount=host.evaluate('__sockets.length');host.evaluate('__sockets.at(-1).close(4000,"Power reconnect test")')
 host.wait_for_function('n=>__sockets.length>n&&leqra.getState().online?.connected',arg=oldcount,timeout=9000)
 check(state(host)['online']['id']==0 and next(t for t in state(host)['tanks'] if t['id']==0)['power']=='grenade','Reconnection preserves authoritative power-up and identity')
 host.wait_for_function('leqra.getState().tanks.find(t=>t.id===0)?.speedTime===0',timeout=9000)
 check(True,'Super speed expires in the browser after the server timer')
 check(not errors,'No JavaScript runtime errors in offline/new online power-ups')
 report={'checks_passed':len(checks),'checks':checks,'javascript_errors':errors,'isolated_assets':a.isolated,'test_only_power_fixture':True,'browser_version':browser.version,'layouts':[[1365,950],[390,844],[320,568],[844,390]]}
 (out/'powerups-results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));browser.close()

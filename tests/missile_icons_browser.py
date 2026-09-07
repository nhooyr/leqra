"""v2.8 shared icons / dodgeable ricochet missiles shipped-client checks. Run TestBrowserFixture, then this script.
The restricted browser cannot navigate to local pages. Assets, storage, location
and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
History calls and encoded invite contents are checked, not real browser navigation.
"""
import argparse,json,re,secrets
from pathlib import Path
from urllib.parse import urlencode,urlsplit,parse_qs
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('url',nargs='?',default='http://127.0.0.1:8790');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/missiles-v28');args=ap.parse_args()
root=Path(__file__).resolve().parents[1]/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(v,label):
 assert v,label
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def fixture(code,power='',player=0,speed=False,shield=False,cover=False,missile_scene=''):
 req=Request(args.url+'/_fixture/powerups',data=json.dumps(dict(code=code,power=power,player=player,speed=speed,shield=shield,cover=cover,missileScene=missile_scene)).encode(),headers={'Content-Type':'application/json'})
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
 # Pixel-for-pixel comparison: the legend calls the SAME powerIcon routine as pickups.
 icon_test=r'''()=>{
 const result=[];const signatures=[];
 for(const icon of document.querySelectorAll('canvas[data-power-icon]')){
  const copy=document.createElement('canvas');copy.width=copy.height=icon.width;
  const c=copy.getContext('2d');c.setTransform(copy.width/26,0,0,copy.width/26,copy.width/2,copy.height/2);
  __test.powerIcon(icon.dataset.powerIcon,c);
  const expected=c.getImageData(0,0,copy.width,copy.height).data,actual=icon.getContext('2d').getImageData(0,0,copy.width,copy.height).data;
  if(!actual.some(v=>v>0)||!actual.every((v,i)=>v===expected[i]))throw Error('Legend differs from maze: '+icon.dataset.powerIcon);
  if(icon.parentElement.textContent.trim())throw Error('Font substitute remains');
  signatures.push(copy.toDataURL());result.push('Matching maze/legend pixels: '+icon.dataset.powerIcon+' at DPR '+devicePixelRatio);
 }
 if(signatures.length!==7||new Set(signatures).size!==7)throw Error('Need seven distinct shared icons');
 return result;
 }'''
 for line in offline.evaluate(icon_test):check(True,line)
 parity=json.loads(root.parent.joinpath('tests/missile-fixtures.json').read_text())
 for case in parity:
  got=offline.evaluate(r'''c=>{
   const T=__test;T.setMode('duel');T.resetPreview();T.setPhase('playing');T.clearBullets();
   T.walls.splice(0,T.walls.length,...c.world.walls);T.tanks.forEach((t,i)=>Object.assign(t,c.tanks[i]));
   const b={...c.bullet,dead:false,trail:[]};T.addBullet(b);
   for(let i=0;i<c.steps;i++){if(c.moveY)T.moveTank(T.tanks[1],0,c.moveY/60);T.updateBullets(1/60);}
   return {bullet:b,alive:T.tanks[1].alive};
  }''',case)
  for field in ['x','y','vx','vy','life','age','rangeLeft','seekDelay','bounces','target']:
   assert abs(got['bullet'].get(field,0)-case['expected'].get(field,0))<1e-6,(case['name'],field,got['bullet'],case['expected'])
  check(got['alive']==case['alive'],'Go / JavaScript flight parity: '+case['name'])
 result=offline.evaluate(r'''()=>{
 const T=__test,passed=[],ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
 const setup=()=>{T.setMode('solo');T.resetPreview();T.setPhase('playing');T.clearBullets();const w=leqra.getState().world;
 T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
 T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:false,invulnerable:0,shield:0,cooldown:0,power:null,speedTime:0}));return w;};
 const missile=(w,x,y)=>({id:10,owner:0,kind:'homing',target:-1,x,y,vx:235,vy:0,r:5,age:.2,life:(w.width+w.height)/235+.5,rangeLeft:w.width+w.height,seekDelay:0,dead:false,trail:[],bounces:0,color:'#d2f65a'});
 let w=setup(),p=T.tanks[0];p.alive=true;T.grantPower(p,'homing');T.fire(p);let b=T.bullets[0];ok(b.rangeLeft===w.width+w.height-28,'Offline missile budget is half perimeter including muzzle');
 w=setup();p=T.tanks[0];p.alive=true;p.x=w.width-24;T.grantPower(p,'homing');T.fire(p);b=T.bullets[0];ok(!b.dead&&b.vx<0&&b.bounces===1&&b.x<w.width-9,'Muzzle-wall contact reflects, without crossing wall');
 w=setup();b=missile(w,w.width-14,210);T.addBullet(b);T.updateBullets(1/30);ok(T.bullets.length===1&&b.vx<0&&b.bounces===1&&b.seekDelay>0,'Offline wall contact survives, reflects, and clears steering');
 w=setup();b=missile(w,100,210);b.rangeLeft=1.25;T.addBullet(b);T.updateBullets(1/60);ok(b.dead&&b.rangeLeft===0&&Math.abs(b.x-101.25)<1e-7,'Offline range exhaustion cannot overshoot mid-tick');
 w=setup();b=missile(w,w.width-14,210);T.addBullet(b);T.tanks[1].alive=true;T.tanks[1].x=w.width-120;
 const before=JSON.stringify(b),segments=T.forecastThreats(T.tanks[1],.65);ok(segments.some(s=>s.vx<0)&&segments.some(s=>s.vx>0),'Bot dodge forecast includes both incoming and reflected missile');ok(JSON.stringify(b)===before,'Bot forecast does not mutate live projectile');
 const projected=T.projectOnlineBullet(b,.1);ok(projected.bounces===1&&projected.vx<0&&projected.x<b.x&&projected.rangeLeft<b.rangeLeft,'Online projectile smoothing continues along reflected wall path');ok(JSON.stringify(b)===before,'Visual extrapolation does not mutate authoritative snapshot');
 b=missile(w,100,210);b.rangeLeft=1.25;const short=T.projectOnlineBullet(b,.1);ok(Math.abs(short.x-101.25)<1e-7&&short.rangeLeft===0,'Online visual extrapolation respects half-perimeter budget');
 w=setup();T.tanks[0].alive=true;T.tanks[0].x=400;T.tanks[0].y=260;T.tanks[1].alive=true;T.tanks[1].x=100;T.tanks[2].alive=true;T.tanks[2].x=180;
 b=missile(w,135,210);b.owner=1;T.steerMissile(b,1/60);ok(b.target===0&&b.vy>0,'Bot missile ignores closer allied bot');
 T.tanks[0].alive=false;T.tanks[2].x=220;T.tanks[2].shield=10;b.target=-1;b.seekDelay=0;b.vx=235;b.vy=0;T.addBullet(b);for(let i=0;i<45;i++)T.updateBullets(1/60);ok(T.tanks[2].alive&&T.tanks[2].shield===10,'Bot missile collision still cannot harm allied shield or tank');
 T.setPhase('menu');T.resetPreview();return passed;
 }''')
 for line in result:check(True,line)
 offline.close()
 # Four actual WebSockets and the shipped renderer, including mobile touch.
 host=load('HOST');host.locator('[data-mode=online]').click();host.locator('#createRoomBtn').click();connected(host);code=state(host)['online']['code']
 phone=load('PHONE',code,(390,844));tiny=load('POCKET',code,(320,568));wide=load('WIDE',code,(844,390));pages=[host,phone,tiny,wide]
 for p in pages:p.wait_for_function('leqra.getState().online?.players.length===4');p.locator('#readyBtn').click()
 host.locator('#startRoomBtn').click()
 for p in pages:p.wait_for_function('leqra.getState().phase==="playing"')
 for line in phone.evaluate(icon_test):check(True,line)
 def scenario(**kwargs):
  data=fixture(code,**kwargs)
  for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g)',arg=data['generation'])
  return data['generation']
 gen=scenario(power='homing',cover=True)
 host.keyboard.down('Space');host.wait_for_timeout(70);host.keyboard.up('Space')
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.bounces>0&&b.vx<0&&b.rangeLeft>0))',arg=gen)
 check(True,'All four clients receive a live reflected homing missile')
 check(host.evaluate('g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.bullets).filter(b=>b.kind==="homing").every(b=>b.x<=325.001)',gen),'Server missile stays on near side of intervening wall')
 check(next(t for t in state(host)['tanks'] if t['id']==1)['alive'],'Cover still protects opponent while missile ricochets')
 host.evaluate('document.querySelector(".sidebar").scrollTop=10000');host.screenshot(path=str(out/'shared-icons-and-wall-bounce.png'))
 tiny.screenshot(path=str(out/'missile-320x568.png'))
 # A new forward press on the target, no boost, escapes a close approach.
 gen=scenario(power='homing',missile_scene='dodge')
 phone.keyboard.down('KeyW');host.keyboard.down('Space');host.wait_for_timeout(70);host.keyboard.up('Space');phone.wait_for_timeout(920);phone.keyboard.up('KeyW')
 check(next(t for t in state(phone)['tanks'] if t['id']==1)['alive'],'Normal-speed online tank survives a sideways dodge')
 check(host.evaluate('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.age>.5&&b.target===-1))',gen),'Dodge breaks server missile lock')
 # Fixture invulnerability isolates full path exhaustion from combat hits.
 gen=scenario(power='homing',missile_scene='range')
 host.keyboard.down('Space');host.wait_for_timeout(70);host.keyboard.up('Space')
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"))',arg=gen)
 host.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="impact"&&e.radius===20))',arg=gen,timeout=12000)
 rows=host.evaluate('g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.bullets.filter(b=>b.kind==="homing"))',gen)
 check(all(0<b['rangeLeft']<=1680 for b in rows) and all(b['rangeLeft']<=a['rangeLeft'] for a,b in zip(rows,rows[1:])),'Live missile has one monotonically decreasing half-perimeter budget')
 check(any(b['bounces']>=1 for b in rows) and rows[-1]['rangeLeft']<12,'Live missile spends its remaining range after multiple wall contacts')
 for p in pages:p.wait_for_function('leqra.getState().bulletCount===0')
 check(True,'Range-exhausted missile disappears for all clients')
 gen=scenario(power='homing',player=1,speed=True,shield=True)
 phone.wait_for_function('leqra.getState().tanks.find(t=>t.id===1)?.power==="homing"')
 cdp=phone.context.new_cdp_session(phone);st=phone.locator('#stickBase').bounding_box();fb=phone.locator('#fireBtn').bounding_box();before=next(t for t in state(phone)['tanks'] if t['id']==1)
 points=[{'x':st['x']+st['width']/2+35,'y':st['y']+st['height']/2,'id':11},{'x':fb['x']+fb['width']/2,'y':fb['y']+fb['height']/2,'id':12}]
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':points});phone.wait_for_timeout(330)
 check(next(t for t in state(phone)['tanks'] if t['id']==1)['x']>before['x']+30 and phone.locator('#fireBtn').evaluate('e=>e.classList.contains("held")'),'Simultaneous mobile steering and missile firing still work')
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 for p in [tiny,phone,wide]:check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No horizontal overflow at '+str(p.viewport_size))
 check(not errors,'No JavaScript exceptions in icon/missile checks')
 report={'checks_passed':len(checks),'checks':checks,'javascript_errors':errors,'browser_version':browser.version,'isolated_assets':True,'server':'local Go WebSocket fixture','go_client_parity_cases':len(parity),'layouts':[[1365,950],[390,844],[320,568],[844,390]]}
 (out/'missile-icons-results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));browser.close()

"""v2.6 shipped-client checks. Run TestBrowserFixture, then this script.
The restricted browser cannot navigate to local pages. Assets, storage, location
and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
History calls and encoded invite contents are checked, not real browser navigation.
"""
import argparse,json,re,secrets
from pathlib import Path
from urllib.parse import urlencode,urlsplit,parse_qs
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('url',nargs='?',default='http://127.0.0.1:8790');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/expansion');args=ap.parse_args()
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

 # The actual offline simulation: no replacement movement or damage code.
 offline=load('OFFLINE')
 result=offline.evaluate(r'''()=>{
  const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
  const setup=()=>{T.setMode('solo');T.resetPreview();T.setPhase('playing');T.clearBullets();const w=leqra.getState().world;
   T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
   T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0}));return T.tanks;
  };
  let ts=setup();T.grantPower(ts[0],'laser');T.grantPower(ts[0],'shield');T.grantPower(ts[0],'speed');
  ok(ts[0].power==='laser'&&ts[0].charges===3&&ts[0].shield===10&&ts[0].speedTime===6,'Offline laser grants three shots alongside speed and shield');
  ok(T.fire(ts[0])&&!ts[1].alive&&ts[2].alive&&ts[0].alive&&T.bullets.length===0,'Offline laser instantly stops at first opponent, never hits owner');
  ok(!T.fire(ts[0])&&ts[0].charges===2,'Offline laser cooldown prevents double fire');
  ok(T.traces.length>0&&T.traces.at(-1).endX>ts[0].x,'Offline beam visual is generated');
  ts=setup();ts[1].shield=10;T.grantPower(ts[0],'laser');T.fire(ts[0]);ok(ts[1].alive&&ts[1].shield===0&&ts[2].alive,'Offline shield absorbs laser and protects tank behind it');
  ts=setup();ts[0].x=129;T.walls.push({x:150,y:0,w:8,h:500});T.grantPower(ts[0],'laser');T.fire(ts[0]);ok(ts[1].alive&&T.traces.at(-1).points[1].x<=147,'Offline barrel cannot shoot laser through nearby wall');
  ts=setup();ts[1].x=100;ts[2].x=180;ts[2].shield=10;ts[0].x=400;T.grantPower(ts[1],'laser');
  ok(T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0)?.target===0,'Laser bot finds player beyond its teammate');
  T.fire(ts[1]);ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[2].shield===10,'Bot laser passes through allies without damaging shields');
  ts=setup();ts[0].angle=-Math.PI/2;T.grantPower(ts[0],'laser');for(let i=0;i<3;i++){ts[0].cooldown=0;T.fire(ts[0]);}
  ok(!ts[0].power&&ts[0].charges===0,'Offline laser expires after three shots');
  T.setMode('duel');T.startRound();ok(T.pickups.length===2,'Local duel starts with two power-ups');
  T.setMode('solo');T.startRound();ok(T.pickups.length===2,'Solo starts with two power-ups');
  for(let i=0;i<30;i++)T.spawnPower();ok(T.pickups.length===5,'Offline arena keeps at most five power-ups');
  const seen=new Set();for(let i=0;i<300;i++){T.pickups.splice(0);T.spawnPower();T.pickups.forEach(p=>seen.add(p.type))}ok(seen.size===7&&seen.has('laser'),'All seven pickup types spawn offline');
  for(const name of ['a','café + & #/?=','🎮 家族','<img src=x onerror=alert(1)>','💥'.repeat(128)])ok(T.validRoomCode(T.cleanRoomCode(name)),'Client accepts room text: '+name.slice(0,20));
  for(const name of ['', ' ', 'x\u0000y','x\ny','a'.repeat(129),'💥'.repeat(129),'\ud800','\u200b'])ok(!T.validRoomCode(T.cleanRoomCode(name)),'Client rejects blank/control/oversize: '+JSON.stringify(name.slice(0,10)));
  ok(T.cleanRoomCode('abc234')==='ABC234'&&T.cleanRoomCode('Room + 🛡️')==='Room + 🛡️','Custom text preserved; old codes remain case-insensitive');
  T.setPhase('menu');T.resetPreview();return passed;
 }''')
 for label in result:check(True,label)
 offline.close()

 host=load('HOST');host.locator('[data-mode=online]').click()
 code="Adam's tanks + café & 💥 #/? = " + secrets.token_hex(2)
 host.locator('#joinCode').fill(code)
 check(host.locator('#joinCode').input_value()==code,'Room field keeps arbitrary text while typing')
 host.locator('#createRoomBtn').click();connected(host)
 check(state(host)['online']['code']==code and state(host)['online']['id']==0,'Create uses supplied arbitrary room name and assigns host')
 history=host.evaluate('__historyCalls');invite=host.evaluate('__location.href')
 check(len(history)==1 and parse_qs(urlsplit(invite).query).get('room')==[code],'Welcome updates History exactly once with encoded room name')
 check(list(parse_qs(urlsplit(invite).query))==['room'] and not urlsplit(invite).fragment,'Address is invite-only: no test flag, token or fragment')
 host.locator('#copyInviteBtn').click();host.wait_for_function('__copied.length>0')
 check(host.evaluate('__copied')==invite,'Copy Invite and updated address use exactly the same URL')
 check(host.evaluate('__sockets.length')==1,'Address update never reloads or creates another socket')

 phone=load('PHONE',code,(390,844));tiny=load('TINY',code,(320,568));wide=load('WIDE',code,(844,390));pages=[host,phone,tiny,wide]
 for i,p in enumerate(pages):
  connected(p);p.wait_for_function('leqra.getState().online.players.length===4')
  check(state(p)['online']['code']==code,'Encoded invite joins same custom-name room '+str(i))
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'No horizontal overflow in custom-name room '+str(i))
  check(p.locator('#pauseBtn').evaluate('e=>e.getBoundingClientRect().right<=innerWidth'),'Header controls stay on-screen '+str(i))
  p.screenshot(path=str(out/f'room-{i}.png'))
 check(all(p.evaluate('__sent.filter(m=>m.type==="join").length')==1 for p in pages[1:]),'Invites directly join once without extra click')
 # Rename and kick stay scoped in the Unicode room.
 phone.locator('#roomCallsign').fill('NEW PHONE');phone.locator('#roomCallsignForm button').click();host.wait_for_function('leqra.getState().online.players.some(p=>p.name==="NEW PHONE")')
 check(True,'In-room rename still broadcasts in custom-name room')
 for p in pages:p.locator('#readyBtn').click()
 host.locator('#startRoomBtn').click()
 for p in pages:p.wait_for_function('leqra.getState().phase==="playing"')
 check(state(host)['pickupCount']>=2,'Online match starts with two power-ups')
 def scenario(power='laser',player=0,speed=False,shield=False,cover=False):
  data=fixture(code,power,player,speed,shield,cover)
  for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g)',arg=data['generation']);p.wait_for_timeout(70)
  return data['generation']
 gen=scenario(speed=True,shield=True)
 host.wait_for_function('document.getElementById("weaponLabel").textContent.includes("LASER")')
 check('×3' in host.locator('#weaponLabel').inner_text(),'Online laser HUD shows three charges')
 check('SPEED' in host.locator('#buffLabel').inner_text() and 'SHIELD' in host.locator('#buffLabel').inner_text(),'Laser can coexist with speed and shields online')
 host.keyboard.down('Space');host.wait_for_timeout(65);host.keyboard.up('Space')
 for p in pages:p.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"))',arg=gen)
 check(True,'All four clients receive server laser beam endpoints')
 host.wait_for_function('!leqra.getState().tanks.find(t=>t.id===1).alive')
 check(next(t for t in state(host)['tanks'] if t['id']==0)['charges']==2,'Server consumes one charge for one laser hit')
 check(state(host)['bulletCount']==0,'Online laser is instantaneous, not a delayed shell')
 # Miss into wall for stable visible screenshot; capture before afterglow expires.
 gen=scenario(cover=True)
 host.keyboard.down('Space');host.wait_for_timeout(50);host.keyboard.up('Space');host.screenshot(path=str(out/'laser-beam.png'))
 host.wait_for_timeout(120)
 check(next(t for t in state(host)['tanks'] if t['id']==1)['alive'],'Live server laser cannot hit opponent behind wall')
 beams=host.evaluate('g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.events||[]).filter(e=>e.type==="laser"&&e.generation===g)',gen)
 check(beams and all(len(e['points'])>2 and e['points'][1]['x']<=327.0001 for e in beams),'Laser beam reflects at the wall face without tunneling')
 # Mobile firing uses existing touch button, with simultaneous thumbstick.
 gen=scenario(player=2,cover=True)
 cdp=tiny.context.new_cdp_session(tiny);rect=tiny.locator('#fireBtn').bounding_box();stickRect=tiny.locator('#stickBase').bounding_box()
 pts=[{'x':rect['x']+rect['width']/2,'y':rect['y']+rect['height']/2,'id':1},{'x':stickRect['x']+stickRect['width']/2+20,'y':stickRect['y']+stickRect['height']/2,'id':2}]
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':pts});tiny.wait_for_timeout(85);cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 tiny.wait_for_function('g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.owner===2))',arg=gen)
 check(True,'Compact-phone Fire button fires server-authoritative laser')
 tiny.screenshot(path=str(out/'phone-laser.png'))
 # Reconnect reads stored arbitrary room name; the session is not confused by +/%.
 session=wide.evaluate('JSON.parse(sessionStorage.getItem("leqra.session"))');old=state(wide)['online']['id'];wide.close()
 host.wait_for_function('id=>leqra.getState().online.players.some(p=>p.id===id&&!p.connected)',arg=old)
 resumed=load('RESTORED',code,(844,390),session);connected(resumed);pages[-1]=resumed
 check(state(resumed)['online']['id']==old,'Reconnect preserves seat in punctuation/Unicode room')
 for p in pages:p.close()

 # Random Create updates the address, too, and Leave clears it.
 random=load('RANDOM');random.locator('[data-mode=online]').click();random.locator('#createRoomBtn').click();connected(random)
 check(len(state(random)['online']['code'])==6 and random.evaluate('new URL(__location).searchParams.get("room")')==state(random)['online']['code'],'Blank-name Create sets random-code invite in address')
 random.locator('#leaveRoomBtn').click();check(random.evaluate('!new URL(__location).searchParams.has("room")'),'Leave removes room from address');random.close()
 restricted=load('RESTRICTED',history_throws=True);restricted.locator('[data-mode=online]').click();restricted.locator('#createRoomBtn').click();connected(restricted)
 check(True,'History restrictions do not break room creation');restricted.close()
 # No HTML interpretation; extra-long unbroken names are contained on phones.
 for name,size in [("<img src=x onerror=alert(1)> & <script>bad()</script>",(320,568)),('💥'*128,(844,390))]:
  p=load('TEXT ONLY',name,size);connected(p)
  check(p.locator('#roomCodeDisplay').inner_text()==name and p.locator('#roomCodeDisplay img,#roomCodeDisplay script').count()==0,'Room name rendered as text, not HTML')
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Long/special room name does not stretch viewport')
  # Reachable actions and non-overlapping header on small touch devices.
  check(p.locator('#leaveRoomBtn').is_visible() and p.locator('#copyInviteBtn').is_visible(),'Room actions remain available with a long name')
  p.screenshot(path=str(out/f'long-name-{size[0]}.png'));p.close()
 check(not errors,'No browser JavaScript errors')
 browser.close()
(out/'results.json').write_text(json.dumps({'checks_passed':len(checks),'checks':checks,'errors':errors,'limitations':'Chromium emulation. Exact shipped assets, synthetic URL/History/storage, real local Go WebSockets. No real navigation or physical-phone testing.'},indent=2,ensure_ascii=False))
print('PASSED',len(checks),flush=True)

"""Real Go-backed Cannon trial with two keyboard pilots, a remote pilot and viewer.
Only the loopback _test.go fixture arranges the cover/target and equips weapons.
Controls, firing, collision, damage, snapshots and drawing are production code.
"""
import argparse,json,re,time,urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('url',nargs='?',default='http://127.0.0.1:8851');ap.add_argument('--output',default='test-output/cannon39-online');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,s):assert ok,s;checks.append(s);print('PASS',s,flush=True)
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+f'}})(new URL({json.dumps(args.url+"/?test=1")}));'+js[i+5:]
def load(c,name):
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''()=>{const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,'localStorage',{value:store({'leqra.muted':'1'})});Object.defineProperty(window,'sessionStorage',{value:store({})});}''')
 p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');p.locator('#joinOtherBtn').click();p.locator('#pilotName').fill(name);return p

def track(p):
 p.evaluate('''()=>{window.wire39=[];__test.online.socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.type==='state')wire39.push(m);});}''')

def cannon_seen(p,owner):
 return p.evaluate('''owner=>{const shots=wire39.flatMap(s=>s.bullets).filter(b=>b.owner===owner&&b.kind==='cannon');return{count:shots.length,correct:shots.every(b=>b.r===10.5&&Math.abs(Math.hypot(b.vx,b.vy)-846)<.0001&&b.bounces===0),crossed:shots.some(b=>b.x>705),max:Math.max(0,...shots.map(b=>b.x))};}''',owner)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  ctx=b.new_context(viewport={'width':1365,'height':950});phone=b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True,device_scale_factor=2)
  host=load(ctx,'CANNON HOST');host.locator('#createRoomBtn').click();host.wait_for_function('leqra.getState().online?.connected');code=host.evaluate('leqra.getState().online.code');hid=host.evaluate('leqra.getState().online.id')
  host.locator('#addLocalBtn').click();host.wait_for_function('leqra.getState().room.players.length===2');pid=host.evaluate("leqra.getState().room.players.find(p=>p.kind==='local').id")
  host.locator('#roomRulesBtn').click();host.locator('#rule-mode').select_option('koth');host.locator('#rule-timeLimit').fill('600');host.locator('#rule-scoreTarget').fill('300');host.locator('#rule-pickupRate').select_option('off');host.locator('#applyRulesBtn').click()
  guest=load(ctx,'REMOTE TARGET');guest.locator('#joinCode').fill(code);guest.locator('#joinRoomBtn').click();guest.wait_for_function('leqra.getState().online?.connected');gid=guest.evaluate('leqra.getState().online.id');guest.locator('#readyBtn').click()
  viewer=load(phone,'VIEWER');viewer.locator('#joinCode').fill(code);viewer.locator('#joinRoomBtn').click();viewer.wait_for_function('leqra.getState().online?.connected');viewer.evaluate('''()=>{const s=leqra.getState();__test.setPlayerSpectating(s.room.players.find(p=>p.id===s.online.id),true);}''');viewer.wait_for_function('leqra.getState().online.spectating')
  if not guest.evaluate('leqra.getState().room.players.find(p=>p.id===leqra.getState().online.id).ready'):guest.locator('#readyBtn').click()
  host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');host.locator('#startRoomBtn').click()
  for p in [host,guest,viewer]:p.wait_for_function('leqra.getState().phase==="playing"');track(p)
  req=urllib.request.Request(args.url+'/_fixture/cannon39',data=json.dumps({'code':code,'shield':True}).encode(),headers={'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=3) as r:setup=json.load(r)
  for p in [host,guest,viewer]:p.wait_for_function('''gen=>__test.online.generation===gen&&__test.online.snapshots.at(-1).tanks.every(t=>t.power==='cannon')''',arg=setup['generation'])
  check(True,'All live clients receive server Cannon grants and the same covered arena')
  host.wait_for_function("document.querySelector('#weaponLabel').textContent.includes('CANNON') && document.querySelector('#weaponLabel2').textContent.includes('CANNON')")
  check(True,'Both local online pilots have independent Cannon HUDs')
  host.bring_to_front();host.keyboard.down('f');host.wait_for_timeout(70);host.keyboard.up('f')
  guest.wait_for_function('id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).shield===0',arg=gid)
  check(guest.evaluate('id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).alive',gid),'Remote tank survives Cannon hit behind two walls because its shield absorbs it')
  for p,label in [(host,'Host'),(guest,'Remote player'),(viewer,'Phone spectator')]:
   seen=cannon_seen(p,hid);check(seen['count']>0 and seen['correct'] and seen['crossed'],label+' sees true-size/speed Cannon cross both walls without a bounce')
  check(viewer.evaluate('leqra.getState().online.spectating'),'Viewing Cannon fire never grants a spectator a tank')
  host.wait_for_function('id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).cooldown===0',arg=hid)
  host.keyboard.down('f');host.wait_for_timeout(70);host.keyboard.up('f')
  guest.wait_for_function('id=>!__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).alive',arg=gid)
  check(True,'Second Cannon shot kills unshielded remote tank behind cover')
  host.wait_for_function('id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).charges===1',arg=hid)
  check(True,'Server charges track two primary shots independently')
  host.keyboard.down('Space');host.wait_for_timeout(70);host.keyboard.up('Space')
  host.wait_for_function("id=>wire39.some(s=>s.bullets.some(b=>b.kind==='cannon'&&b.owner===id&&b.x>705))",arg=pid)
  for p,label in [(host,'Host'),(viewer,'Spectator')]:
   seen=cannon_seen(p,pid);check(seen['count']>0 and seen['correct'] and seen['crossed'],label+' sees Player 2 Space-fired Cannon owned by the correct tank')
  check(host.evaluate("id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).charges===2",pid),'Player 2 consumes its own charge, not Player 1 ammo')
  host.screenshot(path=str(out/'online-cannon.png'));viewer.screenshot(path=str(out/'spectator-cannon-390.png'))
  # Reconnection must preserve a equipped Cannon and not equip the spectator.
  before=host.evaluate('leqra.getState().online.id');host.evaluate('__test.online.socket.close(4000,"Cannon reconnect test")');host.wait_for_function('!leqra.getState().online.connected');host.wait_for_function('leqra.getState().online.connected',timeout=12000)
  check(host.evaluate('leqra.getState().online.id')==before,'Cannon update retains controller identity after reconnection')
  check(host.evaluate("id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).power==='cannon'",pid),'Reconnection preserves still-equipped secondary Cannon')
  check(not errors,'No uncaught errors with server-backed Cannon gameplay')
  (out/'results.json').write_text(json.dumps({'version':'3.9.0','passed':len(checks),'checks':checks,'errors':errors,'limits':'Real Go sockets; exact assets injected with synthetic URL/storage. Deterministic grant/cover only in loopback _test.go fixture.'},indent=2));print('TOTAL',len(checks))
 finally:b.close()

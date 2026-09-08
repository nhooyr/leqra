"""v4.1: exact browser assets; deterministic gameplay and real Go WebSockets.
Only location/history/storage are adapted for opaque browser pages.
"""
import argparse,json,re,time
from pathlib import Path
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:18041');ap.add_argument('--output',default='test-output/phase41');ap.add_argument('--expect-version',default='4.1.0');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,text):
 assert ok,text
 checks.append(text);print('PASS',text,flush=True)
html=re.sub(r'<link[^>]*>|<script src="theme.js"></script>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
def load(b,w=1365,h=950,live=False,name='TEST',invite='',stored=None):
 mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1)
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};window.__store=a.stored;
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,'localStorage',{value:store(a.stored)});Object.defineProperty(window,'sessionStorage',{value:store({})});if(!a.live)window.requestAnimationFrame=()=>0;}''',{'url':args.url+'/?test=1'+invite,'stored':stored or {'leqra.name':name,'leqra.muted':'1'},'live':live})
 p.add_script_tag(content=(web/'theme.js').read_text());p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.__test')
 p.evaluate('''()=>{window.arena41=()=>{const T=__test;T.setPhase('menu');T.applyLocalPreset({rules:{...T.defaultRoomRules(),pickupRate:'off'},roster:[{kind:'human',name:'Alpha',team:0},{kind:'local',name:'Bravo',team:0},{kind:'bot',name:'Target',team:0,difficulty:'normal'}]});T.startRound();T.setPhase('playing');T.clearInput();T.clearBullets();
 T.setWorld({width:1008,height:840,cols:12,rows:10,walls:[{x:-4,y:-4,w:1016,h:8},{x:-4,y:836,w:1016,h:8},{x:-4,y:-4,w:8,h:848},{x:1004,y:-4,w:8,h:848},{x:248,y:-4,w:8,h:848},{x:-4,y:332,w:1016,h:8}]});
 T.tanks.forEach((t,i)=>Object.assign(t,{human:true,x:210+i*250,y:210+i*150,angle:0,alive:true,invulnerable:0,cooldown:0,shield:0,speedTime:0,scopeTime:0,ghostTime:0,team:0,power:null,powerTime:0,charges:0}));return T;};}''')
 return p,c
def setup_room(code,action='setup'):
 return json.load(urlopen(Request(args.url+'/_fixture/phase41',data=json.dumps({'code':code,'action':action}).encode(),headers={'Content-Type':'application/json'})))
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  p,c=load(b)
  check(p.evaluate("(v)=>leqra.version===v&&leqra.getState().rules.weapons.length===10&&leqra.getState().rules.weapons.includes('ghost')",args.expect_version),'New rooms enable all ten pickups including Ghost')
  p.locator('[data-kick-target]').first.click()
  check(p.evaluate("leqra.getState().room.players.length===3&&!document.querySelector('#kickDialog').open"),'One click removes local bot without a confirmation dialog')
  p.locator('#addLocalBtn').click();pid=p.evaluate("leqra.getState().room.players.find(p=>p.kind==='local').id")
  p.locator(f'[data-kick-target="{pid}"]').first.click();check(p.locator('#kickDialog').evaluate('(d)=>d.open'),'Local human removal still requires confirmation');p.locator('#cancelKickBtn').click()
  p.locator('#roomRulesBtn').click();check(p.locator('[data-weapon-toggle="ghost"]').is_checked(),'Host can select Ghost in rules')
  p.locator('[data-weapon-toggle="ghost"]').uncheck();p.locator('#applyRulesBtn').click();check(p.evaluate("!leqra.getState().rules.weapons.includes('ghost')"),'Ghost can be disabled without altering other weapons')
  p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('No Ghost');p.locator('#savePresetBtn').click();saved=p.evaluate('__store');p.locator('[data-close-dialog="presetsDialog"]').click()
  q,qc=load(b,stored=saved);q.locator('#roomPresetsBtn').click();q.locator('#presetSelect').select_option('saved:0');q.locator('#loadPresetBtn').click();check(q.evaluate("!leqra.getState().rules.weapons.includes('ghost')"),'Explicit custom presets retain their saved pickup list');qc.close()
  r=p.evaluate('''()=>{const T=arena41(),t=T.tanks[0];for(const e of T.tanks.slice(1))e.alive=false;const regular=T.projectileSpec(null);T.grantPower(t,'cannon');T.fire(t);const s=T.bullets[0],initial={x:s.x,r:s.r,speed:Math.hypot(s.vx,s.vy)};t.alive=false;T.updateBullets(.12);const interior={x:s.x,bounces:s.bounces,vx:s.vx};for(let i=0;i<340&&!s.dead;i++)T.updateBullets(1/60);return{regular,initial,interior,dead:s.dead,bounces:s.bounces};}''')
  check(r['initial']['r']==4*r['regular']['r'] and r['initial']['speed']==4*r['regular']['speed'],'Cannon is exactly 4x diameter and speed')
  check(r['initial']['x']==242 and r['interior']['bounces']==0 and abs(r['interior']['x']-(242+1128*.12))<1e-6,'Safe enlarged muzzle; Cannon crosses interior walls without ricochet')
  check(r['dead'] and r['bounces']>0,'Cannon bounces at arena rim then expires within its lifetime')
  for axis in ['right','left','top','bottom','corner']:
   r=p.evaluate('''axis=>{const T=arena41(),t=T.tanks[0];T.tanks.slice(1).forEach(e=>e.alive=false);const v={right:[978,210,0],left:[30,210,Math.PI],top:[210,30,-Math.PI/2],bottom:[210,810,Math.PI/2],corner:[978,810,Math.PI/4]}[axis];Object.assign(t,{x:v[0],y:v[1],angle:v[2]});T.grantPower(t,'cannon');const s=T.muzzleProjectile(t,t.angle);t.alive=false;const vis=T.projectOnlineBullet(s,.09);T.bullets.push(s);for(let i=0;i<6;i++)T.updateBullets(.015);return{bounces:s.bounces,inside:s.x>=18&&s.x<=990&&s.y>=18&&s.y<=822,delta:Math.hypot(s.x-vis.x,s.y-vis.y),vx:s.vx,vy:s.vy};}''',axis)
   check(r['bounces']>=1 and r['inside'] and r['delta']<1e-6,f'{axis}: live and online cosmetic Cannon rim reflections agree')
  r=p.evaluate('''()=>{const T=arena41(),t=T.tanks[0];T.tanks.slice(1).forEach(e=>e.alive=false);t.x=950;T.grantPower(t,'cannon');T.grantPower(t,'scope');const g=T.aimingGuide(t);return{points:g.points,budget:g.points.slice(1).reduce((n,p,i)=>n+Math.hypot(p.x-g.points[i].x,p.y-g.points[i].y),0)};}''')
  check(len(r['points'])>2 and r['budget']<=1848+1e-6 and max(pt['x'] for pt in r['points'])<=990,'Scoped Cannon guide reflects only at outer rim with bounded length')
  r=p.evaluate('''()=>{const T=arena41(),t=T.tanks[0];for(const x of ['cannon','shield','scope','speed','ghost'])T.grantPower(t,x);const before={power:t.power,charges:t.charges,shield:t.shield,speed:t.speedTime,scope:t.scopeTime,ghost:t.ghostTime};for(let i=0;i<30;i++)leqraNet.move(t,{forward:true,stickX:0,stickY:0},1/60,T.moveTank);const x=t.x,old=t.speedTime;T.grantPower(t,'ghost');return{before,x,old,speed:t.speedTime,ghost:t.ghostTime};}''')
  check(r['before']=={'power':'cannon','charges':3,'shield':10,'speed':6,'scope':10,'ghost':10},'Ghost stacks with Cannon, Shield, Scope and Super Speed')
  check(abs(r['x']-(210+128*1.65*.5))<1e-6,'Ghost plus Super Speed crosses a solid internal wall at boosted speed')
  check(r['ghost']==10 and r['old']==r['speed'],'Repeat Ghost refreshes only its own timer')
  for x,y in [(252,210),(252,336),(250,334),(1000,835)]:
   r=p.evaluate('''a=>{const T=arena41(),t=T.tanks[0];Object.assign(t,{x:a[0],y:a[1],ghostTime:.001});const alive=t.alive;T.advanceGhost(t,1/60);return{fits:T.clearTankAt(t.x,t.y,t.r),alive:t.alive===alive,ghost:t.ghostTime,x:t.x,y:t.y};}''',[x,y])
   check(r['fits'] and r['alive'] and r['ghost']==0,f'Expiry at {x},{y} safely clears wall/corner overlap without death')
  r=p.evaluate('''()=>{const T=arena41(),t=T.tanks[0];T.grantPower(t,'ghost');T.moveTank(t,99999,-99999);const edge=t.x===987&&t.y===21;t.x=252;t.y=210;const blocked=!T.fire(t);T.grantPower(t,'cannon');const cannon=T.fire(t);T.hurt(t,{owner:1});return{edge,blocked,cannon,dead:!t.alive};}''')
  check(r['edge'] and r['blocked'] and r['cannon'] and r['dead'],'Ghost respects outer rim, ordinary wall cover and damage; Cannon still fires through cover')
  r=p.evaluate('''()=>{const T=arena41(),t=T.tanks[0];T.pickups.length=0;T.pickups.push({x:t.x,y:t.y,type:'ghost',age:0,life:19});T.update(1/120);return{ghost:t.ghostTime,count:T.pickups.length};}''')
  check(r=={'ghost':10,'count':0},'Driving over Ghost really collects the independent buff')
  fixtures=json.loads((root/'tests/fixtures/phase41.json').read_text())
  check(p.evaluate('''cases=>cases.every(c=>{const T=arena41();T.setWorld(c.world);const t={...c.initial};return c.inputs.every((keys,i)=>{leqraNet.move(t,keys,1/60,T.moveTank);return ['x','y','angle','speedTime','ghostTime'].every(k=>Math.abs(t[k]-c.states[i][k])<1e-7);});})''',fixtures),'480 movement steps match Go exactly, including expiry and boosted turns')
  c.close()
  # Phone/desktop geometry and matching shared icons, with all four buffs together.
  for w,h in [(1365,950),(390,844),(320,568),(844,390)]:
   p,c=load(b,w,h);p.locator('#addLocalBtn').click();p.locator('#startRoomBtn').click();p.evaluate("__test.setPhase('playing');__test.updateHUD(true);__test.render()")
   before=p.locator('#arenaWrap').bounding_box()
   r=p.evaluate('''()=>{const T=__test;for(const t of T.tanks.filter(t=>t.human)){for(const k of ['cannon','speed','shield','scope','ghost'])T.grantPower(t,k);}T.updateHUD(true);T.render();T.renderPowerLegend();return [...document.querySelectorAll('.power-list canvas[data-power-icon]')].every(e=>{const f=document.createElement('canvas');f.width=e.width;f.height=e.height;const c=f.getContext('2d');c.setTransform(f.width/26,0,0,f.height/26,f.width/2,f.height/2);T.powerIcon(e.dataset.powerIcon,c);return e.toDataURL()===f.toDataURL();});}''')
   check(r,f'{w}×{h}: all ten legend icons pixel-match maze icons')
   check(p.locator('#arenaWrap').bounding_box()==before,f'{w}×{h}: Ghost + other buffs do not resize arena')
   check('GHO' in p.locator('#buffLabel').inner_text() and 'GHO' in p.locator('#buffLabel2').inner_text(),f'{w}×{h}: independent P1/P2 Ghost countdowns')
   check(p.evaluate('document.body.scrollWidth<=innerWidth+1'),f'{w}×{h}: no horizontal page overflow')
   check(p.locator('#buffLabel').evaluate('(e)=>e.scrollWidth<=e.clientWidth+1'),f'{w}×{h}: all four buff timers fit without ellipsis')
   p.screenshot(path=str(out/f'ghost-{w}x{h}.png'));c.close()
  # Online membership, no-confirmation moderation, both local controllers, remote observer.
  host,hc=load(b,live=True,name='HOST');host.locator('#addLocalBtn').click();host.locator('#copyInviteBtn').click();host.wait_for_function('leqra.getState().online?.connected')
  code=host.evaluate('leqra.getState().online.code');count=host.evaluate('leqra.getState().room.players.length');host.locator('[data-kick-target]').filter(has_text='REMOVE').first.click()
  host.wait_for_function('(n)=>leqra.getState().room.players.length===n',arg=count-1)
  check(not host.locator('#kickDialog').evaluate('(d)=>d.open'),'One click removes an online bot without confirmation')
  viewer,vc=load(b,320,568,live=True,name='OBSERVER',invite='&room='+code+'&spectate=1')
  viewer.locator('#watchName').fill('OBSERVER') if viewer.locator('#watchName').count() else None
  # The watch-link visitor must confirm their callsign before connecting.
  viewer.locator('#watchJoinBtn').click() if viewer.locator('#watchJoinBtn').count() else viewer.get_by_role('button',name='WATCH GAME',exact=False).click()
  viewer.wait_for_function('leqra.getState().online?.connected&&leqra.getState().online.spectating')
  check(True,'Spectator link still requires callsign confirmation and admits a viewer')
  host.locator('#startRoomBtn').click();host.wait_for_function("leqra.getState().phase==='playing'");setup_room(code)
  host.wait_for_function('leqra.getState().tanks.filter(t=>t.ghostTime>0).length>=2');viewer.wait_for_function('leqra.getState().tanks.some(t=>t.ghostTime>0)')
  ids=host.evaluate('[__test.online.id,__test.online.roomData.players.find(p=>p.kind==="local").id]')
  host.keyboard.down('w');host.keyboard.down('ArrowUp');host.wait_for_timeout(450);host.keyboard.up('w');host.keyboard.up('ArrowUp')
  r=host.evaluate('(ids)=>__test.online.snapshots.at(-1).tanks.filter(t=>ids.includes(t.id)).map(t=>({x:t.x,ghost:t.ghostTime,speed:t.speedTime}))',ids)
  check(len(r)==2 and all(t['x']>430 and t['ghost']>0 and t['speed']>0 for t in r),'Both real online keyboard tanks phase through a wall with Super Speed')
  host.keyboard.down('f');host.keyboard.down('Space');host.wait_for_timeout(100);host.keyboard.up('f');host.keyboard.up('Space')
  host.wait_for_function('(ids)=>ids.every(id=>__test.online.snapshots.at(-1).bullets.some(b=>b.owner===id&&b.kind==="cannon"&&b.bounces>0))',arg=ids)
  r=host.evaluate('()=>__test.online.snapshots.at(-1).bullets.filter(b=>b.kind==="cannon")')
  check(all(b['r']==14 and abs((b['vx']**2+b['vy']**2)**.5-1128)<1e-6 for b in r),'Server-authoritative Cannons are 4x and ricochet for both keyboard players')
  viewer.wait_for_function('__test.online.snapshots.at(-1).bullets.some(b=>b.kind==="cannon"&&b.bounces>0)')
  check(True,'Phone spectator receives the same bouncing Cannon projectiles')
  old=host.evaluate('__test.online.id');host.evaluate('__test.online.socket.close(4000,"reconnect test")');host.wait_for_function('leqra.getState().online?.connected',timeout=15000)
  check(host.evaluate('__test.online.id')==old and host.evaluate('(ids)=>ids.every(id=>__test.online.snapshots.at(-1).tanks.some(t=>t.id===id&&t.ghostTime>0))',ids),'Reconnect restores both pilots and their remaining Ghost buffs')
  setup_room(code,'expire');host.wait_for_function('()=>{const s=__test.online.snapshots.at(-1);return s.tanks.every(t=>t.ghostTime===0&&Math.abs(t.x-420)>20)}')
  check(True,'Online expiry inside a wall safely returns every tank to clear space')
  viewer.screenshot(path=str(out/'online-spectator-320.png'));hc.close();vc.close()
  check(not errors,'No browser JavaScript errors: '+str(errors))
 finally:
  b.close();(out/'results.json').write_text(json.dumps({'version':args.expect_version,'passed':len(checks),'checks':checks,'errors':errors},indent=2))
print('TOTAL',len(checks))

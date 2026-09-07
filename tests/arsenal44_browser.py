"""v4.4 exact-asset Chromium checks. About:blank injection + loopback fixture.
No production grant endpoint; screenshots and checks are from the shipped code.
"""
import argparse,json,re,time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8445');ap.add_argument('--output',default='test-output/arsenal44');ap.add_argument('--local-only',action='store_true');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[];contexts=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
def wait(p,s,**kwargs):return p.wait_for_function(s,polling=30,**kwargs)
def load(b,size=(1365,950),scheme='dark',live=False,code=None,watch=False,name='PILOT'):
 w,h=size;mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1,color_scheme=scheme);contexts.append(c);p=c.new_page();p.set_default_timeout(9000);p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 q={'test':'1'}
 if code:q['room']=code
 if watch:q['spectate']='1'
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};
 for(const name of ['localStorage','sessionStorage']){const d=name==='localStorage'?{'leqra.name':a.name,'leqra.muted':'1'}:{};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}
 if(!a.live)window.requestAnimationFrame=()=>0;
 const WS=WebSocket;window.WebSocket=class extends WS{constructor(...args){super(...args);this.addEventListener('message',e=>{const s=JSON.parse(e.data);if(s.type==='state')window.__lastRaw=s;});}};
 }''',dict(url=a.url+'/?'+urlencode(q),live=live,name=name))
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);wait(p,'window.__test&&leqra.version==="4.4.0"');p.evaluate('__test.render()');return p

def fixture(code,route='arsenal44',**kw):
 data=json.dumps(dict(code=code,**kw)).encode();return json.load(urlopen(Request(a.url+'/_fixture/'+route,data=data,headers={'Content-Type':'application/json'}),timeout=5))
def dims(p):return p.locator('#arenaWrap').evaluate('(e)=>({w:e.clientWidth,h:e.clientHeight})')
def play(p):
 p.locator('#startRoomBtn').click();p.evaluate('''()=>{__test.setPhase('playing');for(const t of __test.tanks){t.human=true;t.invulnerable=600;t.vx=t.vy=0;t.angle=0;}__test.updateHUD(true);__test.render();}''')
def rings(p,n):
 return p.evaluate('''n=>{const t=__test.tanks[0];t.shield=10;t.shieldCharges=n;t.invulnerable=0;const c=document.getElementById('arena').getContext('2d'),oldArc=c.arc,oldStroke=c.stroke,oldBegin=c.beginPath;let arc=null,got=[];c.beginPath=function(...a){arc=null;return oldBegin.apply(this,a)};c.arc=function(x,y,r,...a){arc=r;return oldArc.call(this,x,y,r,...a)};c.stroke=function(...a){if(arc>=25&&arc<=43)got.push(arc);return oldStroke.apply(this,a)};try{__test.drawTank(t)}finally{c.arc=oldArc;c.stroke=oldStroke;c.beginPath=oldBegin}return got;}''',n)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');ok=False
 try:
  for size in [(1365,950),(390,844),(320,568),(844,390)]:
   for skin in ['dark','light']:
    p=load(b,size,skin);tag=f'{skin}-{size[0]}x{size[1]}'
    check(p.evaluate('leqraTheme.palette.accent')==('#00c8ff' if skin=='dark' else '#a100ff'),tag+' primary accent')
    check(p.locator('[data-tank-color]').count()==4,tag+' four host tank palettes')
    if size==(1365,950):
     matched=p.evaluate('''()=>[...document.querySelectorAll('.power-list canvas[data-power-icon]')].map(icon=>{const c=document.createElement('canvas');c.width=icon.width;c.height=icon.height;const ctx=c.getContext('2d');ctx.setTransform(c.width/26,0,0,c.width/26,c.width/2,c.height/2);__test.powerIcon(icon.dataset.powerIcon,ctx);return[icon.dataset.powerIcon,c.toDataURL()===icon.toDataURL()]})''')
     for kind,equal in matched:check(equal,tag+' '+kind+' legend matches shared maze drawing')
    p.locator('[data-tank-color="0"]').select_option('5');check(p.evaluate('__test.localRoom.players[0].colorIndex')==5,tag+' local tank color applied')
    check(p.locator('[data-tank-color="0"] option').count()==9,tag+' eight choices plus inherit')
    if size==(1365,950):p.screenshot(path=str(out/('room-'+skin+'.png')))
    p.locator('#roomRulesBtn').click();p.locator('#rule-teamColor1').select_option('6');p.locator('#rule-teamColor2').select_option('4')
    check(p.locator('#rule-teamColor1').bounding_box()['height']<=42,tag+' compact team color selector')
    check(p.locator('#rule-teamColor1 option').count()==8,tag+' exactly eight team choices')
    if size in [(1365,950),(320,568)]:p.screenshot(path=str(out/('rules-'+tag+'.png')))
    p.locator('#applyRulesBtn').click();check(p.evaluate('__test.currentRules().teamColors[0]')==6,tag+' team color saved')
    preset=p.evaluate('__test.snapshotPreset()');check(preset['roster'][0]['colorIndex']==5 and preset['rules']['teamColors'][:2]==[6,4],tag+' preset preserves both color choices')
    play(p);before=dims(p)
    for n in range(1,6):check(len(rings(p,n))==n,f'{tag} exactly {n} shield ring(s)')
    p.evaluate('''()=>{const t=__test.tanks[0];t.shield=10;t.shieldCharges=5;for(const k of ['speed','scope','ghost','scatter'])__test.grantPower(t,k);__test.updateHUD(true);__test.updateCombatFeedback(true);__test.render();}''')
    check(dims(p)==before,tag+' stacked buffs do not resize arena')
    check('SHD×5' in p.locator('#buffLabel').inner_text(),tag+' HUD shows five shields')
    if size[0]<=390:check(p.locator('#buffLabel').evaluate('(e)=>e.clientWidth>=e.scrollWidth'),tag+' all compact buff badges fit without truncation')
    check('SHOTGUN' in p.locator('#weaponLabel').inner_text(),tag+' Shotgun renamed in HUD')
    check('Machine gun' in p.locator('.power-list').inner_text() and 'Triple shot' not in p.locator('.power-list').inner_text(),tag+' legend names updated')
    p.screenshot(path=str(out/('shields-'+tag+'.png')))
    state=p.evaluate('JSON.stringify({x:__test.tanks[0].x,y:__test.tanks[0].y,team:__test.tanks[0].team,color:__test.tanks[0].color})')
    p.evaluate('leqraTheme.setPreference(leqraTheme.resolved==="dark"?"light":"dark");__test.render()')
    check(dims(p)==before and p.evaluate('JSON.stringify({x:__test.tanks[0].x,y:__test.tanks[0].y,team:__test.tanks[0].team,color:__test.tanks[0].color})')==state,tag+' live appearance switch preserves physics and dimensions')
    p.close()
  # Deterministic local weapons and spawn selection, no browser clock dependency.
  p=load(b);play(p)
  data=p.evaluate('''()=>{const chosen=[];const old=Math.random;try{for(let i=0;i<5;i++){Math.random=()=> (i+.1)/5;chosen.push(__test.choosePickup(['shield','rapid','scatter']))}}finally{Math.random=old}return chosen}''')
  check(data==['shield','shield','shield','rapid','scatter'],'JS exact shield selection weight 3:1:1')
  data=p.evaluate('''()=>{const t=__test.tanks[0];t.invulnerable=0;t.shield=0;t.shieldCharges=0;for(let i=0;i<8;i++)__test.grantPower(t,'shield');let stages=[__test.shieldCount(t)];for(let i=0;i<5;i++){t.invulnerable=0;__test.hurt(t,{owner:1});stages.push(__test.shieldCount(t));}return{stages,alive:t.alive,shield:t.shield}}''')
  check(data==dict(stages=[5,4,3,2,1,0],alive=True,shield=0),'Local shield cap and one-charge damage agree with Go')
  for power,speed,radius in [('rapid',846,3.5/3),('scatter',846,3.5)]:
   spec=p.evaluate('(k)=>__test.projectileSpec(k)',power);check(spec['speed']==speed and abs(spec['r']-radius)<1e-9,power+' exact local size and speed')
  p.evaluate('''()=>{__test.clearBullets();for(const t of __test.tanks)t.invulnerable=600;const t=__test.tanks[0];t.ghostTime=0;__test.grantPower(t,'rapid');window.__seen=new Set();}''');p.keyboard.down('f')
  p.evaluate('''()=>{for(let i=0;i<240;i++){__test.update(1/120);for(const b of __test.bullets)if(b.owner===0)__seen.add(b.id)}}''');p.keyboard.up('f')
  count=p.evaluate('__seen.size');check(119<=count<=121,f'Local 120Hz physics emits Machine gun at 60Hz ({count} in 2s)')
  check(p.evaluate('__test.bullets.filter(b=>b.owner===0).length')<=91,'Local machine-gun lifetime bounds live rounds')
  check(p.evaluate('__test.tanks[0].cooldown')==0,'Local machine-gun cooldown is zero')
  p.evaluate('''()=>{const t=__test.tanks[0];t.invulnerable=0;t.shield=10;t.shieldCharges=5;__test.hurt(t,{owner:t.id,kind:'scatter'});__test.updateHUD(true);__test.render()}''');check(p.evaluate('__test.shieldCount(__test.tanks[0])')==5,'Local Shotgun self hit never consumes shield')
  p.close()
  if not a.local_only:
   host=load(b,live=True,name='HOST');host.locator('#addLocalBtn').click();host.locator('[data-tank-color="0"]').select_option('6');host.locator('#copyInviteBtn').click();wait(host,'__test.online.connected&&__test.online.roomData?.players.some(p=>p.kind==="local")');code=host.evaluate('__test.online.code');pid=host.evaluate('__test.online.id');p2id=host.evaluate('__test.online.roomData.players.find(p=>p.kind==="local").id')
   guest=load(b,scheme='light',live=True,code=code,name='FRIEND');wait(guest,'__test.online.connected');gid=guest.evaluate('__test.online.id');viewer=load(b,(320,568),'light',True,code,True,'WATCHER');viewer.locator('#joinRoomBtn').click();wait(viewer,'__test.online.connected&&__test.online.spectating')
   check(guest.locator('[data-tank-color]').count()==0 and viewer.locator('[data-tank-color]').count()==0,'Guests and spectators cannot edit tank colors')
   wait(host,f'document.querySelector(\'[data-tank-color="{gid}"]\')');host.locator(f'[data-tank-color="{gid}"]').select_option('4');wait(guest,f'__test.online.roomData.players.find(p=>p.id==={gid}).colorIndex===4')
   check(guest.evaluate(f'__test.online.roomData.players.find(p=>p.id==={gid}).color')=='#ffc46b','Host selection replicated as stable canonical color')
   check(guest.evaluate('leqraTheme.assetColor("#ffc46b")')!=host.evaluate('leqraTheme.assetColor("#ffc46b")'),'Same online tank uses each viewer’s theme variant')
   guest.locator('#readyBtn').click();wait(host,'!document.querySelector("#startRoomBtn").disabled');host.locator('#startRoomBtn').click();wait(host,'__test.phase==="playing"');wait(viewer,'__test.phase==="playing"')
   gen=fixture(code,'combat42',action='setup',weapon='rapid')['generation'];wait(host,'g=>__test.online.generation===g',arg=gen);wait(viewer,'g=>__test.online.generation===g',arg=gen)
   fixture(code,action='shield',player=pid,count=7);fixture(code,action='shield',player=p2id,count=3);wait(host,f'__test.online.snapshots.at(-1).tankMap.get({pid}).shieldCharges===5')
   check(host.evaluate(f'__test.online.snapshots.at(-1).tankMap.get({p2id}).shieldCharges')==3,'Go independently stacks both local pilots')
   wait(viewer,f'__test.online.snapshots.at(-1).tankMap.get({pid}).shieldCharges===5');check(True,'Spectator receives authoritative shield charges')
   fixture(code,action='hit',player=pid);wait(host,f'__test.online.snapshots.at(-1).tankMap.get({pid}).shieldCharges===4');check(True,'Online shield hit consumes exactly one charge')
   before=dims(host);host.keyboard.down('f');host.keyboard.down('Space');host.wait_for_timeout(1350);host.keyboard.up('f');host.keyboard.up('Space');host.wait_for_timeout(120)
   counts=host.evaluate('ids=>ids.map(id=>__test.online.snapshots.at(-1).tankMap.get(id).shotSerial)',[pid,p2id]);check(min(counts)>=60,'Both online machine guns sustain continuous fire: '+str(counts))
   raw=host.evaluate('__lastRaw');check(len(raw.get('machineBullets',[]))>20,'Server uses compact high-rate machine-gun snapshots')
   check(host.evaluate('__test.online.snapshots.at(-1).bullets.filter(b=>b.kind==="rapid"&&Math.abs(b.r-3.5/3)<1e-9).length')>20,'Browser expands compact shots with correct geometry')
   check(host.evaluate('__test.presentationMetrics.previews')>30,'Machine gun retains immediate local previews')
   check(dims(host)==before,'Online stream and shield hits do not change arena size')
   check(host.locator('#cooldownText1').inner_text()=='READY · CONTINUOUS','Continuous-fire feedback has no false cooldown')
   host.screenshot(path=str(out/'online-stream-dark.png'));viewer.screenshot(path=str(out/'online-shields-light-320.png'))
   gen=fixture(code,'combat42',action='setup',weapon='scatter')['generation'];wait(host,'g=>__test.online.generation===g',arg=gen);host.keyboard.press('f');host.keyboard.press('Space');host.wait_for_timeout(180)
   pellets=host.evaluate('(ids)=>__test.online.snapshots.at(-1).bullets.filter(b=>ids.includes(b.owner))',[pid,p2id]);check(len(pellets)==6 and all(b['kind']=='scatter' and abs((b['vx']**2+b['vy']**2)**.5-846)<.02 for b in pellets),'Both local online Shotguns emit three high-speed pellets')
   token=host.evaluate('__test.online.token');host.evaluate('__test.online.socket.close(4000,"regression")');wait(host,'!__test.online.connected');wait(host,'__test.online.connected',timeout=15000);check(host.evaluate('__test.online.token')==token,'Reconnect retains both pilots and palette identity')
   check(host.evaluate('__test.online.roomData.players.find(p=>p.id===__test.online.id).colorIndex')==6,'Selected tank color survives reconnect')
   fixture(code,'combat42',action='win',player=pid);wait(host,'__test.phase==="matchOver"',timeout=12000);wait(viewer,'__test.phase==="matchOver"');check(host.locator('#cooldownText1').inner_text()=='MATCH COMPLETE','Victory feedback remains stable with new weapons')
   viewer.screenshot(path=str(out/'victory-light.png'))
  check(not errors,'No uncaught browser errors: '+str(errors));ok=True
 finally:
  for c in contexts:c.close()
  b.close();(out/'results.json').write_text(json.dumps(dict(version='4.4.0',completed=ok,passed=len(checks),checks=checks,errors=errors),indent=2))
print('TOTAL',len(checks))

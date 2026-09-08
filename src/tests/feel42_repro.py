"""Deterministic browser regressions, exact shipped assets (optional v4.1 baseline).
A fake monotonic clock and read-only snapshots isolate rendering from scheduling.
This is not a WAN/frame-rate benchmark. No production code is instrumented on disk.
"""
import argparse, json, re, zipfile
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--assets');ap.add_argument('--baseline');ap.add_argument('--output',default='test-output/feel42-repro');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
def assets(path):return {k:(Path(path)/k).read_text() for k in ['game.js','netcode.js','index.html','style.css']}
def load(b,src,w=1365,h=950):
 c=b.new_context(viewport={'width':w,'height':h},is_mobile=w<760 or h<620,has_touch=w<760 or h<620)
 p=c.new_page();errors=[];p.on('pageerror',lambda e:errors.append(str(e)))
 html=re.sub(r'<link[^>]*>','',src['index.html']);html=re.sub(r'<script src="[^"]+" defer></script>','',html).replace('</head>','<style>'+src['style.css']+'</style></head>');p.set_content(html)
 p.evaluate('''()=>{window.__clock=1000;Object.defineProperty(performance,'now',{value:()=>window.__clock});window.requestAnimationFrame=()=>0;
 for(const name of ['localStorage','sessionStorage']){const d={'leqra.muted':'1'};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}
 window.__location=new URL('http://127.0.0.1/?test=1');window.__history={replaceState(){}};}''')
 js=src['game.js'].replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
 js=js.replace('window.__test={', '''window.__test={ setupNetwork42:()=>{mode='online';online.connected=true;online.id=0;online.code='TEST42';online.seq=0;online.socket={readyState:1,bufferedAmount:0,send(){},close(){}};online.roomData={...localRoom,code:'TEST42',phase:'playing',host:0};resetOnlineMotion();online.generation=-1;},''',1)
 p.add_script_tag(content=src['netcode.js']);p.add_script_tag(content=js);p.wait_for_function('window.__test')
 p.evaluate('''()=>{window.net42=()=>{const T=__test;T.startRound();const world={cols:12,rows:10,width:1008,height:840,walls:[{x:-4,y:-4,w:1016,h:8,axis:'h'},{x:-4,y:836,w:1016,h:8,axis:'h'},{x:-4,y:-4,w:8,h:848,axis:'v'},{x:1004,y:-4,w:8,h:848,axis:'v'}]};
 const ts=T.tanks.map((t,i)=>({...t,bot:false,x:200+i*84,y:210,angle:0,alive:true,cooldown:0,cooldownTotal:.34,shotSerial:0,spawnSerial:1,ack:0,ackSteps:0}));T.setupNetwork42();
 window.snap42={tick:60,generation:1,phase:'playing',round:1,phaseTime:0,roundClock:70,winner:-1,scores:[0,0,0,0,0,0,0,0],tanks:ts,bullets:[],pickups:[],events:[],rules:T.currentRules(),objectives:null,world};
 T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);return T;};}''')
 return p,c,errors

def probe(b,src):
 p,c,errors=load(b,src);result={}
 try:
  result['buttonWriterConflict']=p.evaluate('''()=>{const T=__test;T.startRound();T.setPhase('playing');const t=T.tanks[0];t.cooldown=.32;t.cooldownTotal=.34;T.updateCombatFeedback(true);const a=document.querySelector('#fireLabel').textContent;__clock+=1;T.updateHUD();const b=document.querySelector('#fireLabel').textContent;return{before:a,after:b,conflict:a!==b};}''')
  result['frozenRound']=p.evaluate('''()=>{const T=net42(),labels=new Set(),values=new Set();snap42.phase='roundOver';snap42.winner=0;snap42.tanks[0].cooldown=.21;for(let k=0;k<120;k++){__clock+=1000/120;if(k%4===0){snap42.tick+=2;T.receiveOnlineState(structuredClone(snap42));}T.renderOnlineMotion(1/120,__clock);T.updateCombatFeedback(true);labels.add(document.querySelector('#cooldownText1').textContent);values.add(document.querySelector('#cooldownFill1').style.transform);}return{labels:[...labels],distinctFillValues:values.size};}''')
  result['remoteBirth']=p.evaluate('''()=>{const T=net42();const bullet={id:101,owner:1,x:320,y:210,vx:282,vy:0,r:3.5,age:.05,life:5,color:'#ff9679',bounces:0,kind:'',shotSerial:1,spawnSerial:1,pellet:0};__clock+=66;snap42.tick=64;snap42.bullets=[bullet];T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);const early=T.bullets.find(b=>b.id===101)?.x??null;__clock+=66;snap42.tick=68;snap42.bullets[0].x=338.8;snap42.bullets[0].age+=.066666;T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);const future=T.bullets.find(b=>b.id===101)?.x??null;T.online.buffer.time=65*1000/60;T.renderOnlineMotion(0,__clock);const later=T.bullets.find(b=>b.id===101)?.x??null;return{early,future,later,backwards:future!==null&&later<future};}''')
  if 'previewOnlineFire' in src['game.js']:
   result['laserWithFullAmmo']=p.evaluate("""()=>{const T=net42();const t=snap42.tanks[0];t.power='laser';t.charges=3;t.powerTime=10;snap42.tick+=2;snap42.bullets=Array.from({length:5},(_,i)=>({id:200+i,owner:0,x:320+i*30,y:630,vx:282,vy:0,r:3.5,age:.7,life:4,color:t.color,bounces:0,kind:'',shotSerial:0,spawnSerial:1,pellet:0}));__clock+=34;T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);T.previewOnlineFire(false,{fire:true},__clock);const n=T.online.shots.previews.size;const trace=T.traces.at(-1),before=trace?.life;__clock+=100;T.onlineEffect({type:'laser',player:0,spawnSerial:1,shotSerial:1,x:200,y:210,endX:284,endY:210,color:t.color,points:[{x:200,y:210},{x:284,y:210}]},T.online.snapshots.at(-1));return{previews:n,traces:T.traces.length,lifeUnchanged:T.traces.at(-1)?.life===before,authoritativeBullets:T.online.snapshots.at(-1).bullets.length};}""")
  result['errors']=errors
 finally:c.close()
 return result
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');report={}
 try:
  if a.baseline:
   with zipfile.ZipFile(a.baseline) as z:old={k:z.read('leqra-online/web/'+k).decode() for k in ['game.js','netcode.js','index.html','style.css']}
   report['baseline']=probe(b,old)
  src=assets(a.assets or r/'web');report['updated']=probe(b,src)
  u=report['updated'];assert not u['buttonWriterConflict']['conflict'],u
  assert u['frozenRound']['labels']==['ROUND COMPLETE'] and u['frozenRound']['distinctFillValues']==1,u
  assert u['remoteBirth']['later'] is not None and not u['remoteBirth']['backwards'] and not u['errors'],u
  assert u['laserWithFullAmmo']=={'previews':1,'traces':1,'lifeUnchanged':True,'authoritativeBullets':5},u
  checks=[]
  for w,h in [(1365,950),(390,844),(320,568),(844,390)]:
   p,c,errors=load(b,src,w,h)
   try:
    p.locator('#addLocalBtn').click();p.locator('#startRoomBtn').click()
    result=p.evaluate('''()=>{const T=__test;T.setPhase('playing');const before=document.querySelector('#arenaWrap').getBoundingClientRect().toJSON();const outputs=[];for(const phase of ['playing','roundOver','matchOver','paused','countdown']){T.setPhase(phase);for(const t of T.tanks){t.cooldown=.19;t.cooldownTotal=.34;}T.updateHUD(true);T.updateCombatFeedback(true);outputs.push([phase,document.querySelector('#cooldownText1').textContent,document.querySelector('#cooldownText2').textContent]);}const after=document.querySelector('#arenaWrap').getBoundingClientRect().toJSON();T.setPhase('roundOver');T.updateHUD(true);T.render();return{outputs,before,after,overflow:document.body.scrollWidth>innerWidth+1};}''')
    assert not result['overflow'] and result['before']['height']==result['after']['height'],result
    assert all(x[1]==x[2] for x in result['outputs']),result
    assert result['outputs'][1][1]=='ROUND COMPLETE' and result['outputs'][2][1]=='MATCH COMPLETE',result
    p.screenshot(path=str(out/f'result-{w}x{h}.png'));checks.append({'viewport':[w,h],**result});assert not errors,errors
   finally:c.close()
  report['layoutChecks']=checks;report['passed']=True
 finally:
  b.close();(out/'results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

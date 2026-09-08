"""v4.10 focused browser checks: stable Ghost HUD, 10s powers, 30s pickups, Shotgun icon, grenade-team avoidance."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/polish410');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.10.0'")

 # Ghost wall block changes only the text, not the underlying colored readiness fill.
 ghost=p.evaluate("""()=>{const t=__test.tanks[0];__test.setPhase('playing');Object.assign(t,{x:100,y:100,alive:true,ghostTime:10,power:null,cooldown:.2,cooldownTotal:.34,shield:0});__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});__test.updateCombatFeedback(true);const before=document.querySelector('#cooldownFill1').style.transform;__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[{x:90,y:80,w:20,h:50,axis:'v',line:100}]});__test.updateCombatFeedback(true);return{before,inside:document.querySelector('#cooldownFill1').style.transform,text:document.querySelector('#cooldownText1').textContent};}""")
 check(ghost['text']=='IN WALL · MOVE TO FIRE','Ghost wall block keeps IN WALL text')
 check(ghost['before']==ghost['inside'] and ghost['inside']!='scaleX(0)','Ghost wall crossing does not gray/empty cooldown indicator')

 durations=p.evaluate("""()=>{const kinds=['shield','speed','scope','ghost','rapid','scatter','homing','grenade','laser','cannon'],t=__test.tanks[0],out={};for(const k of kinds){Object.assign(t,{shield:0,shieldCharges:0,speedTime:0,speedStacks:0,scopeTime:0,ghostTime:0,power:null,powerTime:0,charges:0,cooldown:0,cooldownTotal:0});__test.grantPower(t,k);out[k]=k==='shield'?t.shield:k==='speed'?t.speedTime:k==='scope'?t.scopeTime:k==='ghost'?t.ghostTime:t.powerTime;}return out;}""")
 check(all(abs(v-10)<1e-9 for v in durations.values()),'all timed power-up effects use 10 seconds')
 life=p.evaluate("""()=>{__test.pickups.length=0;__test.spawnPower();return __test.pickups[0]?.life}""")
 check(abs(life-30)<1e-9,'new uncollected pickups use 30-second lifetime')

 bounds=p.evaluate("""()=>{const cv=document.createElement('canvas');cv.width=cv.height=40;const c=cv.getContext('2d');c.translate(20,20);__test.powerIcon('scatter',c);const d=c.getImageData(0,0,40,40).data;let x0=40,x1=-1,y0=40,y1=-1;for(let y=0;y<40;y++)for(let x=0;x<40;x++)if(d[(y*40+x)*4+3]){x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);}return{w:x1-x0+1,h:y1-y0+1};}""")
 check(bounds['w']>bounds['h']*1.5,'Shotgun icon has a clearly horizontal silhouette')

 avoid=p.evaluate("""()=>{const r={...__test.currentRules(),mode:'elimination',teamMode:'teams',friendlyFire:false};__test.setLocalRules(r);const ts=__test.tanks,t=ts[0],ally=ts[1],enemy=ts[2];Object.assign(t,{x:100,y:210,angle:0,r:17,team:1,difficulty:'easy',ghostTime:0});Object.assign(ally,{x:60,y:210,team:1});Object.assign(enemy,{x:420,y:210,team:2});const ctrl={angle:0,drive:1},d={speed:89,turn:2.8};const trial=owner=>{__test.clearBullets();__test.addBullet({id:owner+10,owner,kind:'grenade',x:150,y:210,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,ctrl,d)};const friendly=trial(ally.id),own=trial(t.id),hostile=trial(enemy.id);__test.currentRules().friendlyFire=true;const friendlyFF=trial(ally.id);return{friendly,own,hostile,friendlyFF};}""")
 check(avoid['friendly'] is None,'bot ignores harmless friendly grenade when friendly fire is off')
 check(avoid['own'] is not None,'bot avoids its own grenade')
 check(avoid['hostile'] is not None,'bot avoids enemy grenade')
 check(avoid['friendlyFF'] is not None,'bot avoids friendly grenade when friendly fire is on')
 check(not errors,'no uncaught browser errors: '+str(errors))
 c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.10.0','passed':len(checks),'checks':checks,'errors':errors,'shotgunBounds':bounds,'durations':durations},indent=2));print('TOTAL',len(checks))

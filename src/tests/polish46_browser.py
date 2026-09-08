"""v4.6 focused browser checks: Q controls, weapon tuning, replay/restart, icon distinction."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/polish46');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},has_touch=True,is_mobile=True,color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.6.0'")
 check(p.evaluate("__test.bindings[0].fire")=='KeyQ','Player 1 default Fire is Q')
 check('Q / SPACE' in p.locator('#manualContent').inner_text(),'single-player Space alias is retained with Q')
 # Giant dimensions make the half-perimeter range unambiguous.
 p.evaluate("__test.setWorld({width:1344,height:1176,cols:16,rows:14,walls:[]});const t=__test.tanks[0];t.cooldown=0;__test.grantPower(t,'rapid');__test.fire(t)")
 mg=p.evaluate("({life:__test.bullets[0].life,speed:Math.hypot(__test.bullets[0].vx,__test.bullets[0].vy),trail:__test.bullets[0].trail.length})")
 check(abs(28+mg['life']*mg['speed']-(1344+1176))<1e-6,'Machine gun has half-perimeter total range including the muzzle path')
 p.evaluate("const t=__test.tanks[0];t.invulnerable=0;__test.hurt(t,{owner:t.id,kind:'rapid'})")
 check(p.evaluate("__test.tanks[0].alive"),'Machine gun cannot damage its sender')
 # More than 22 reflections must not truncate the requested W+H path budget.
 p.evaluate("""()=>{__test.clearBullets();__test.setWorld({width:1344,height:1176,cols:16,rows:14,walls:[{x:-4,y:-4,w:8,h:1184,axis:'v',line:0},{x:80,y:-4,w:8,h:1184,axis:'v',line:84}]});__test.addBullet({id:991,owner:7,kind:'rapid',x:42,y:42,vx:846,vy:0,r:3.5/3,age:0,life:(1344+1176-28)/846,color:'#fff',bounces:0,trail:[],dead:false});for(let i=0;i<290;i++)__test.updateBullets(1/120)}""")
 bounce=p.evaluate("({dead:__test.bullets[0]?.dead??true,bounces:__test.bullets[0]?.bounces??0,life:__test.bullets[0]?.life??0,trail:__test.bullets[0]?.trail?.length??-1})")
 check(not bounce['dead'] and bounce['bounces']>22,'Machine gun range survives the old 22-bounce shell ceiling')
 check(bounce['trail']==0,'Machine gun skips unused trail-history allocation')
 p.evaluate("for(let i=0;i<80;i++)__test.updateBullets(1/120)")
 check(p.evaluate("__test.bullets.length")==0,'Machine gun expires at its half-perimeter path budget')
 # Grenade fuse and expanded blast.
 p.evaluate("__test.clearBullets();const t=__test.tanks[0];t.cooldown=0;__test.grantPower(t,'grenade');__test.fire(t)")
 check(abs(p.evaluate("__test.bullets[0].life")-10)<1e-9,'Grenade fuse is ten seconds')
 # Shared icon routine must produce visibly distinct laser and shotgun pixels.
 icons=p.evaluate("""()=>{function pix(k){const c=document.createElement('canvas');c.width=c.height=32;const x=c.getContext('2d');x.translate(16,16);__test.powerIcon(k,x);return Array.from(x.getImageData(0,0,32,32).data)}const a=pix('laser'),b=pix('scatter');let d=0;for(let i=0;i<a.length;i++)d+=Math.abs(a[i]-b[i]);return d;}""")
 check(icons>5000,'Laser icon is clearly distinct from Shotgun icon')
 # Local pause menu offers a one-click restart.
 p.evaluate("__test.startRound();__test.setPhase('playing');document.getElementById('pauseBtn').click()")
 check(not p.locator('#restartLocalBtn').is_hidden(),'local pause menu shows Restart match')
 p.locator('#restartLocalBtn').click();check(p.evaluate("__test.phase")=='countdown','Restart match immediately starts the same local setup')
 # Win dialog offers a quick replay alongside Back to Room.
 p.evaluate("__test.setPhase('matchOver');__test.showVictory(0)")
 check(not p.locator('#victoryAgainBtn').is_hidden(),'win popup shows Play Again')
 p.locator('#victoryAgainBtn').click();check(p.evaluate("__test.phase")=='countdown','Play Again immediately starts another local match')
 check(not errors,'no uncaught browser errors: '+str(errors))
 p.screenshot(path=str(out/'v46-mobile.png'));c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.6.0','passed':len(checks),'checks':checks,'errors':errors},indent=2));print('TOTAL',len(checks))

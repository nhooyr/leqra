"""v4.9 focused browser checks: grenade-body avoidance, quarter-range Machine gun, version/manual UI."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/polish49');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.9.0'")
 # Machine gun spec uses one quarter of the full maze perimeter = (W+H)/2 total path.
 spec=p.evaluate("""()=>{__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});return __test.projectileSpec('rapid')}""")
 expected=(504+420)/(2*(282*3))
 check(abs(spec['life']-expected)<1e-9,'Machine gun client range is one quarter of maze perimeter')
 # Stationary grenade in the driving line causes avoidance even for Chill/basic bot tuning.
 avoid=p.evaluate("""()=>{const t=__test.tanks[0];Object.assign(t,{x:100,y:210,angle:0,r:17,difficulty:'easy',ghostTime:0});__test.clearBullets();__test.addBullet({id:1,owner:1,kind:'grenade',x:158,y:210,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,{angle:0,drive:1},{speed:89,turn:2.8})}""")
 check(avoid is not None and (abs(avoid['angle'])>.15 or avoid['drive']<=.25),'bot steers/brakes instead of headbutting grenade body')
 # Being inside the blast radius alone should not alter a clear route.
 clear=p.evaluate("""()=>{const t=__test.tanks[0];__test.clearBullets();__test.addBullet({id:2,owner:1,kind:'grenade',x:180,y:330,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,{angle:0,drive:1},{speed:89,turn:2.8})}""")
 check(clear is None,'bot does not avoid the grenade full explosion radius')
 # UI wording and version.
 p.click('#roomControlsBtn')
 check('leqra v4.9.0' in p.locator('#controlsDialog').inner_text(),'Controls menu shows game version')
 p.evaluate("document.querySelector('#controlsDialog').close()")
 manual=p.locator('#manualContent').inner_text()
 check('Use Controls menu to change keys.' in manual,'Field Manual wording says Controls menu')
 check('Use Controls to change keys.' not in manual,'old Field Manual wording removed')
 check('Quarter-perimeter range.' in p.locator('.power-list').text_content(),'Machine gun legend describes quarter-perimeter range')
 check(not errors,'no uncaught browser errors: '+str(errors))
 c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.9.0','passed':len(checks),'checks':checks,'errors':errors},indent=2));print('TOTAL',len(checks))

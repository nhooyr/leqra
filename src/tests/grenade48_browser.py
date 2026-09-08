"""v4.8 focused browser check: long-fuse grenade cruises before late braking."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/grenade48');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.8.0'")
 ratios=p.evaluate("""()=>({at5:__test.grenadeDragFactor(10,5),at8:__test.grenadeDragFactor(10,2),at9:__test.grenadeDragFactor(10,1),final:__test.grenadeDragFactor(10,0)})""")
 check(ratios['at5']>.87,'grenade retains over 87% speed halfway through fuse')
 check(ratios['at8']>.74,'grenade retains over 74% speed with two seconds left')
 check(.39<ratios['at9']<.50,'grenade brakes strongly during final second approach')
 check(.09<ratios['final']<.12,'grenade finishes fuse near 10% launch speed')
 # Forecast uses the same curve and now advances remaining fuse time.
 forecast=p.evaluate("""()=>{__test.setWorld({width:10000,height:10000,cols:100,rows:100,walls:[]});const b={kind:'grenade',owner:7,x:5000,y:5000,vx:205,vy:0,r:6,life:10,bounces:0};const q=__test.grenadeForecast(b,5);return {speed:Math.hypot(q.vx,q.vy),life:q.life,x:q.x}}""")
 check(forecast['speed']/205>.87 and abs(forecast['life']-5)<.02,'AI grenade forecast uses cruise-phase drag and advances fuse')
 check(not errors,'no uncaught browser errors: '+str(errors))
 c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.8.0','passed':len(checks),'checks':checks,'errors':errors,'ratios':ratios,'forecast':forecast},indent=2));print('TOTAL',len(checks))

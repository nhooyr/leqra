"""v4.17 branding/storage-migration regression checks."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.17-branding');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':1365,'height':950},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};window.__store={'ricochet.name':'LEGACY PILOT','ricochet.muted':'1','ricochet.difficulty':'hard','ricochet.local2Name':'LEGACY P2','leqra.wins':'7'};window.__session={'ricochet.session':'{\"code\":\"OLD\",\"token\":\"tok\",\"name\":\"LEGACY PILOT\",\"spectating\":false,\"at\":1}'};const store=d=>({getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,'localStorage',{value:store(window.__store)});Object.defineProperty(window,'sessionStorage',{value:store(window.__session)});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']: p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&window.leqra&&leqra.version==='4.23.2'")
 check(p.title()=='leqra — Tank Arena','document title uses lowercase leqra')
 check(p.locator('.brand-name').inner_text()=='leqra','header wordmark is exactly lowercase leqra')
 check('leqra — a mobile-friendly tank maze game' in p.locator('meta[name="description"]').get_attribute('content'),'meta description uses leqra')
 check('leqra.' in p.locator('#lobbyScreen h2').inner_text().lower(),'landing hero uses leqra')
 check(p.evaluate("typeof leqra==='object'&&leqra.version==='4.23.2'"),'canonical public browser API is leqra v4.23.2')
 check(p.evaluate("typeof leqraNet==='object'&&typeof leqraTheme==='object'"),'browser helper globals use leqra names')
 check(p.evaluate("typeof window.Ricochet==='undefined'&&typeof window.RicochetNet==='undefined'&&typeof window.RicochetTheme==='undefined'"),'old product-named browser globals are not exposed')
 migrated=p.evaluate("""()=>({name:__store['leqra.name'],muted:__store['leqra.muted'],difficulty:__store['leqra.difficulty'],p2:__store['leqra.local2Name'],wins:__store['leqra.wins'],session:__session['leqra.session']})""")
 check(migrated['name']=='LEGACY PILOT' and migrated['muted']=='1' and migrated['difficulty']=='hard' and migrated['p2']=='LEGACY P2','legacy local settings migrate into leqra namespace')
 check(migrated['wins']=='7','existing leqra setting wins over any legacy value')
 check(json.loads(migrated['session'])['code']=='OLD','legacy reconnect session migrates into leqra namespace')
 check(p.locator('.game-version').inner_text().strip()=='leqra v4.23.2','Controls version footer uses lowercase leqra')
 check(not errors,'no uncaught browser errors: '+str(errors))
 p.screenshot(path=str(out/'leqra-v417-branding.png'));c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.23.2','passed':len(checks),'checks':checks,'errors':errors,'migrated':migrated},indent=2));print('TOTAL',len(checks))

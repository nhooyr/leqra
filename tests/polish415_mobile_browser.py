"""v4.15 narrow-phone layout smoke checks for Ultra Wide and fixed-height feedback."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.15-mobile');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},color_scheme='dark',has_touch=True,is_mobile=True);p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.31.0'");p.evaluate('__test.createLocalRoom()');p.wait_for_timeout(20)
 p.evaluate("""()=>{__test.setLocalRules({...__test.currentRules(),mapSize:'ultrawide'});__test.addRoomSeat('local')}""");p.locator('#startRoomBtn').click();p.wait_for_timeout(20);p.evaluate("""()=>{__test.setPhase('playing');__test.showStartingControls();__test.updateHUD(true);__test.render()}""")
 metrics=p.evaluate("""()=>{const body=document.documentElement,wrap=document.querySelector('#arenaWrap').getBoundingClientRect(),under=document.querySelector('.underbar').getBoundingClientRect(),before=under.height;__test.setPilotFeedback(1,'LASER · RICOCHETS · MAZE-PERIMETER RANGE',99);__test.updateHUD(true);return{scrollWidth:body.scrollWidth,clientWidth:body.clientWidth,wrapLeft:wrap.left,wrapRight:wrap.right,underBefore:before,underAfter:document.querySelector('.underbar').getBoundingClientRect().height,p1:document.querySelector('#pilotLoadout1').hidden,p2:document.querySelector('#pilotLoadout2').hidden,world:leqra.getState().world};}""")
 check(metrics['scrollWidth']<=metrics['clientWidth']+1,'Ultra Wide mobile page has no horizontal document overflow')
 check(metrics['wrapLeft']>=-1 and metrics['wrapRight']<=391,'arena container stays inside the 390px viewport')
 check(metrics['world']['cols']==24 and metrics['world']['rows']==14,'mobile uses the actual 24×14 Ultra Wide world')
 check(not metrics['p1'] and not metrics['p2'],'both local pilot loadouts remain available on narrow mobile')
 check(abs(metrics['underBefore']-metrics['underAfter'])<0.6,'P2 feedback does not grow the mobile status underbar')
 check(not errors,'no uncaught mobile browser errors: '+str(errors))
 p.evaluate('__test.render()');p.screenshot(path=str(out/'v415-mobile.png'),full_page=True);c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.31.0','passed':len(checks),'checks':checks,'errors':errors,'metrics':metrics},indent=2));print('TOTAL',len(checks))

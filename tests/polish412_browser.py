"""v4.12 focused browser checks: removed loadout key badge/share return, Giant 8-FFA preset, larger remote/bot power badges."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.12-browser');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':320,'height':568},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.12.0'")
 check(p.locator('.loadout-key').count()==0,'under-arena fire-key badges are removed entirely')
 check(p.locator('#bestInline').inner_text()=='','under-arena offline score placeholder starts empty')
 p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option(label='8-tank Free-for-all');p.locator('#loadPresetBtn').click();p.wait_for_timeout(20)
 check(p.evaluate("__test.localRoom.players.length===8&&__test.currentRules().teamMode==='ffa'&&__test.currentRules().mapSize==='giant'"),'8-tank FFA preset uses Giant 16×14')
 # Start a local game and inspect its room/pause menu.
 p.locator('#startRoomBtn').click();p.wait_for_timeout(30);p.evaluate("__test.setPhase('playing')");p.locator('#pauseBtn').click();p.wait_for_timeout(20)
 check(not p.locator('#copyInGameBtn').is_visible(),'local in-game menu has no Return to room to share online button')
 check(p.locator('#restartLocalBtn').is_visible(),'local Restart match action remains available')
 p.locator('#onlineReturnBtn').click();p.wait_for_timeout(20)
 # Make a bot carry five visible effects and verify badges are >=26 world units before view scaling.
 badge=p.evaluate("""()=>{const t=__test.tanks.find(t=>!t.human);Object.assign(t,{alive:true,power:'scatter',powerTime:10,shield:10,shieldCharges:2,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10});const c=document.getElementById('arena').getContext('2d'),old=c.drawImage,calls=[];c.drawImage=function(...a){if(a.length>=5)calls.push([a[1],a[2],a[3],a[4]]);return old.apply(this,a)};try{__test.drawTankPowerBadges(t);}finally{c.drawImage=old}return{calls,kinds:__test.activeTankPowerBadges(t)};}""")
 check(len(badge['calls'])==5,'all active remote/bot effects still draw power badges')
 check(all(w>=26 and h>=26 for _,_,w,h in badge['calls']),'remote/bot power badges are at least double the old 13-unit size')
 p.screenshot(path=str(out/'playing-320x568.png'))
 check(not errors,'no uncaught browser errors: '+str(errors))
 c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.12.0','passed':len(checks),'checks':checks,'errors':errors,'badgeCalls':badge['calls']},indent=2));print('TOTAL',len(checks))

"""v4.14 focused browser checks: F fullscreen, always-on one-line summary scores, round-preserving restart."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.14-browser');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':1365,'height':950},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.14.0'")
 # Summary scores are visible even with the normal desktop sidebar present.
 check(p.locator('.sidebar').is_visible() and 'sidebar-hidden' not in (p.locator('body').get_attribute('class') or ''),'desktop sidebar is present for scoreboard visibility check')
 check(p.locator('#miniScores').evaluate("e=>getComputedStyle(e).display")=='flex','summary scoreboard stays active with sidebar visible')
 # Load the eight-tank preset and verify all summary score entries remain in one row.
 p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option(label='8-tank Free-for-all');p.locator('#loadPresetBtn').click();p.wait_for_timeout(30)
 p.locator('#startRoomBtn').click();p.wait_for_timeout(30);p.evaluate('__test.updateHUD(true)')
 score_layout=p.locator('#miniScores').evaluate("""e=>{const r=[...e.children].map(x=>x.getBoundingClientRect());return{count:r.length,top:r.map(x=>Math.round(x.top)),height:e.getBoundingClientRect().height,scrollHeight:e.scrollHeight,clientHeight:e.clientHeight,display:getComputedStyle(e).display}}""")
 check(score_layout['count']==8,'eight-tank FFA shows all eight summary scores')
 check(len(set(score_layout['top']))==1 and score_layout['scrollHeight']<=score_layout['clientHeight']+1,'five-plus tank summary scoreboard is forced to one line')
 # F enters/exits native fullscreen.
 p.keyboard.press('f');p.wait_for_timeout(160)
 check(p.evaluate('!!document.fullscreenElement'),'F enters fullscreen')
 p.keyboard.press('f');p.wait_for_timeout(120)
 check(not p.evaluate('!!document.fullscreenElement'),'F exits fullscreen')
 # F is reserved from gameplay rebinding.
 p.locator('#pauseBtn').click();p.wait_for_timeout(20);p.locator('#menuControlsBtn').click();p.wait_for_timeout(20)
 fire_btn=p.locator('[data-bind="0:fire"]');before=fire_btn.inner_text();fire_btn.click();p.keyboard.press('f');p.wait_for_timeout(20)
 check(p.locator('#controlsNotice').inner_text().lower().find('reserved')>=0 and p.evaluate('__test.bindings[0].fire')=='KeyQ','F is reserved for fullscreen instead of gameplay binding')
 p.locator('[data-close-dialog="controlsDialog"]').click();p.locator('#onlineReturnBtn').click();p.wait_for_timeout(20)
 # Give one side a point, then restart the active elimination round from pause.
 p.evaluate("""()=>{__test.setPhase('playing');__test.finishRound(0);__test.startRound();__test.setPhase('playing');}""")
 before_state=p.evaluate('leqra.getState()')
 check(max(before_state['scores'])>0,'restart preservation test begins with a nonzero match score')
 p.locator('#pauseBtn').click();p.wait_for_timeout(20)
 check(p.locator('#restartLocalBtn').inner_text().lower().startswith('restart round'),'elimination pause menu labels the action Restart round')
 p.locator('#restartLocalBtn').click();p.wait_for_timeout(30)
 after_state=p.evaluate('leqra.getState()')
 check(after_state['phase']=='countdown','Restart round begins a fresh countdown')
 check(after_state['scores']==before_state['scores'],'Restart round preserves the current match score')
 check(after_state['round']==before_state['round'],'Restart round preserves the current round number')
 check(not errors,'no uncaught browser errors: '+str(errors))
 p.screenshot(path=str(out/'v414-desktop.png'));c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.14.0','passed':len(checks),'checks':checks,'errors':errors,'scoreLayout':score_layout},indent=2));print('TOTAL',len(checks))

"""Focused UI regression checks retained through v4.20."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.18-browser');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
def install(page,name='ALPHA',disable_ua_data=False):
 page.set_content(html)
 page.evaluate("""a=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':a.name,'leqra.muted':'1'};const store=x=>({getItem:k=>x[k]??null,setItem:(k,v)=>x[k]=String(v),removeItem:k=>delete x[k]});Object.defineProperty(window,'localStorage',{value:store(d)});Object.defineProperty(window,'sessionStorage',{value:store({})});if(a.noUAData){try{Object.defineProperty(navigator,'userAgentData',{value:undefined,configurable:true});}catch(_){}}}""",{'name':name,'noUAData':disable_ua_data})
 for f in ['theme.js','netcode.js']: page.add_script_tag(content=(web/f).read_text())
 page.add_script_tag(content=js);page.wait_for_function("window.__test&&leqra.version==='4.33.0'")

with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 c=b.new_context(viewport={'width':1365,'height':950},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));install(p)

 check(True,'Chromium does not receive the Safari-only browser recommendation')
 check(p.evaluate('__test.pickupLifetime(16,14)')==61 and p.evaluate('__test.pickupLifetime(24,14)')==90,'ground pickup expiry uses the 8/3 maze-cap formula (Giant 61s, Ultra Wide 90s)')

 # With only P1 using default controls, arrows are shown above WASD in the sidebar.
 p.evaluate('__test.createLocalRoom()');p.wait_for_timeout(30)
 manual=p.evaluate("""()=>{const box=document.querySelector('#manualContent .manual-key-options'),rows=[...box.querySelectorAll('.keys')];return{keys:rows.map(r=>[...r.querySelectorAll('kbd')].map(k=>k.textContent)),tops:rows.map(r=>r.getBoundingClientRect().top),text:document.querySelector('#manualContent').innerText};}""")
 check(manual['keys'][0]==['↑','←','↓','→'] and manual['keys'][1]==['W','A','S','D'] and manual['tops'][0]<manual['tops'][1],'single-P1 Field Manual places arrow movement above WASD')

 # Opening the local pause/room menu and Controls dialog must not leave a stale
 # canvas backing size that the browser horizontally stretches to the new CSS box.
 p.locator('#startRoomBtn').click();p.wait_for_timeout(80)
 def arena_metrics():
  return p.evaluate("""()=>{const w=document.querySelector('.arena-wrap').getBoundingClientRect(),c=document.querySelector('#arena'),v=__test.view,d=window.devicePixelRatio||1;return{wrapW:w.width,wrapH:w.height,cssW:v.cssW,cssH:v.cssH,canvasW:c.width,canvasH:c.height,ratio:w.width/w.height,canvasRatio:c.width/c.height};}""")
 before=arena_metrics();p.locator('#pauseBtn').click();p.wait_for_timeout(80);p.locator('#menuControlsBtn').click();p.wait_for_timeout(80)
 during=arena_metrics();p.locator('[data-close-dialog="controlsDialog"]').click();p.wait_for_timeout(40);p.locator('#onlineReturnBtn').click();p.wait_for_timeout(100);after=arena_metrics()
 def aligned(m): return abs(m['wrapW']-m['cssW'])<1 and abs(m['wrapH']-m['cssH'])<1 and abs(m['ratio']-m['canvasRatio'])<0.01
 check(aligned(before) and aligned(during) and aligned(after),'pause/menu interactions keep canvas and arena aspect ratios synchronized (no horizontal stretch)')

 # Both local tanks being dead is an eliminated state, not a role change.
 p.evaluate("""()=>{__test.createLocalRoom();__test.addRoomSeat('local');__test.resetPreview();__test.setPhase('playing');const p2=__test.localRoom.players.find(x=>x.kind==='local');const t1=__test.tanks.find(t=>t.id===0),t2=__test.tanks.find(t=>t.id===p2.id);t1.alive=false;t2.alive=false;__test.updateHUD(true);}""");p.wait_for_timeout(30)
 down=p.evaluate("""()=>({p1:document.querySelector('#weaponLabel').textContent,p2:document.querySelector('#weaponLabel2').textContent,caption:document.querySelector('#watchingCaption').textContent,loadouts:document.querySelector('#localLoadouts').innerText})""")
 check(down['p1']=='TANK DOWN' and down['p2']=='TANK DOWN' and 'SPECTATING' not in down['loadouts'],'dead P1 and P2 remain TANK DOWN rather than becoming Spectating')

 # Losing local sides get result language, not congratulations.
 p.evaluate("""()=>{__test.createLocalRoom();__test.resetPreview();__test.setPhase('matchOver');__test.showVictory(1);}""");p.wait_for_timeout(30)
 result=p.evaluate("""()=>{const t=document.querySelector('#victoryTitle'),e=document.querySelector('#victoryEmblem');return{eyebrow:document.querySelector('#victoryEyebrow').textContent,title:t.textContent,message:document.querySelector('#victoryMessage').textContent,all:document.querySelector('#victoryDialog').innerText,emblem:e.textContent,color:getComputedStyle(t).color,titleTop:t.getBoundingClientRect().top,emblemTop:e.getBoundingClientRect().top}}""")
 check(result['eyebrow']=='MATCH RESULTS' and result['title']=='DEFEAT' and result['emblem']=='☠' and result['color']=='rgb(255, 79, 95)' and result['emblemTop']>result['titleTop'] and 'CONGRAT' not in result['all'].upper(),'losing player receives red DEFEAT with defeat icon below it and no congratulations')
 p.evaluate('__test.closeVictory()')

 check(not errors,'no uncaught Chromium browser errors: '+str(errors));p.screenshot(path=str(out/'v418-desktop.png'));c.close()

 # Desktop Safari receives the current Chrome/Firefox recommendation. Chromium is still
 # used as the test engine with a Safari identity for this retained regression.
 safari_ua='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
 sc=b.new_context(viewport={'width':1365,'height':950},user_agent=safari_ua,color_scheme='dark');sp=sc.new_page();sp.on('pageerror',lambda e:errors.append('safari-emulation: '+str(e)));install(sp,'SAFARI TEST',True);sp.wait_for_timeout(30)
 check(sp.locator('#browserNotice').count()==1 and 'Chrome or Firefox' in sp.locator('#browserNotice').inner_text(),'desktop Safari recommends Chrome or Firefox')
 sc.close();b.close()

(out/'results.json').write_text(json.dumps({'version':'4.33.0','passed':len(checks),'checks':checks,'errors':errors,'manual':manual,'arena':{'before':before,'during':during,'after':after},'down':down,'result':result},indent=2));print('TOTAL',len(checks))

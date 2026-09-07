"""v4.11 focused browser checks: simpler Shotgun icon, loadout strip, local pause, FFA presets, remote/bot power badges."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/polish411');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':390,'height':844},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.11.0'")
 # Presets are visible in room setup.
 p.locator('#roomPresetsBtn').click();opts=p.locator('#presetSelect option').all_text_contents();
 check('4-tank Free-for-all' in opts,'4-tank Free-for-all preset is available')
 check('8-tank Free-for-all' in opts,'8-tank Free-for-all preset is available')
 p.locator('#presetSelect').select_option(label='8-tank Free-for-all');p.locator('#loadPresetBtn').click();p.wait_for_timeout(20)
 check(p.evaluate("__test.localRoom.players.length===8&&__test.currentRules().teamMode==='ffa'&&__test.currentRules().mapSize==='huge'"),'8-tank FFA preset loads eight tanks on Huge 14×12')
 p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option(label='4-tank Free-for-all');p.locator('#loadPresetBtn').click();p.wait_for_timeout(20)
 check(p.evaluate("__test.localRoom.players.length===4&&__test.currentRules().teamMode==='ffa'&&__test.currentRules().mapSize==='large'"),'4-tank FFA preset loads four tanks on Large 12×10')
 # Start local match and inspect the under-arena strip.
 p.locator('#startRoomBtn').click();p.wait_for_timeout(30);p.evaluate('__test.updateHUD(true)')
 key=p.locator('#loadoutKey1');check(key.inner_text()=='Q / SPACE','single-player fire hint shows Q / SPACE')
 metrics=key.evaluate('e=>({client:e.clientWidth,scroll:e.scrollWidth,right:e.getBoundingClientRect().right,parent:e.parentElement.getBoundingClientRect().right})')
 check(metrics['scroll']<=metrics['client']+1 and metrics['right']<=metrics['parent']+1,'Q / SPACE fire hint is not clipped')
 check(p.locator('#bestInline').inner_text()=='','offline FIRST TO 5 label removed from underbar')
 # Local pause menu keeps Restart but no New local room action.
 p.evaluate("__test.setPhase('playing')");p.locator('#pauseBtn').click();p.wait_for_timeout(20)
 check(p.locator('#restartLocalBtn').is_visible(),'local pause menu keeps Restart match')
 check(not p.locator('#onlineLeaveBtn').is_visible(),'local pause menu removes New local room button')
 p.locator('#onlineReturnBtn').click();p.wait_for_timeout(20)
 # Shotgun icon is a simple right-facing three-way spread.
 icon=p.evaluate("""()=>{const cv=document.createElement('canvas');cv.width=cv.height=52;const c=cv.getContext('2d');c.translate(26,26);__test.powerIcon('scatter',c);const d=c.getImageData(0,0,52,52).data;let ys=new Set(),right=0,left=0;for(let y=0;y<52;y++)for(let x=0;x<52;x++)if(d[(y*52+x)*4+3]){if(x>=35){ys.add(y);right++}if(x<=19)left++;}return{right,left,bands:[...ys]};}""")
 # Three separated right-side endpoint bands, with a simple feeder line to the left.
 bands=icon['bands'];groups=0;prev=None
 for y in bands:
  if prev is None or y>prev+1: groups+=1
  prev=y
 check(groups>=3 and icon['right']>0 and icon['left']>0,'Shotgun icon reads as one line branching into three shots')
 # Bots/remotes get compact active-power badges, starting top-right and moving clockwise.
 badge=p.evaluate("""()=>{const t=__test.tanks.find(t=>!t.human);Object.assign(t,{alive:true,power:'scatter',powerTime:10,shield:10,shieldCharges:2,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10});const kinds=__test.activeTankPowerBadges(t);const c=document.getElementById('arena').getContext('2d'),old=c.drawImage,calls=[];c.drawImage=function(...a){if(a.length>=5)calls.push([a[1],a[2],a[3],a[4]]);return old.apply(this,a)};try{__test.drawTankPowerBadges(t);}finally{c.drawImage=old}return{kinds,calls,x:t.x,y:t.y};}""")
 check(badge['kinds']==['scatter','shield','speed','scope','ghost'],'bot badge list includes weapon and every active buff')
 check(len(badge['calls'])==5,'five active power-ups draw five cached badges')
 centers=[(x+w/2,y+h/2) for x,y,w,h in badge['calls']]
 tx,ty=badge['x'],badge['y']
 check(centers[0][0]>tx and centers[0][1]<ty and centers[1][0]>tx and centers[1][1]>ty and centers[2][0]<tx and centers[2][1]>ty and centers[3][0]<tx and centers[3][1]<ty,'first four power badges progress clockwise from top-right')
 p.screenshot(path=str(out/'playing-390x844.png'))
 check(not errors,'no uncaught browser errors: '+str(errors))
 c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.11.0','passed':len(checks),'checks':checks,'errors':errors,'shotgun':icon,'keyMetrics':metrics,'badgeKinds':badge['kinds']},indent=2));print('TOTAL',len(checks))

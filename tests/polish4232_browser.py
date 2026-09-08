"""v4.32.0 mobile-default and supplemental-fire regressions."""
import json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1];web=root/'web';out=root/'tests/results/v4.32.0-polish';out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script[^>]*src="[^"]+"[^>]*></script>','',html);html=html.replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label):
 assert ok,label;checks.append(label);print('PASS',label,flush=True)
def setup(page,data):
 page.on('pageerror',lambda exc:errors.append(str(exc)));page.set_content(html);page.evaluate('''data=>{window.__location=new URL('http://example.test/?test=1');window.__history={state:null,replaceState(){}};const store=obj=>({getItem:k=>Object.hasOwn(obj,k)?obj[k]:null,setItem:(k,v)=>obj[k]=String(v),removeItem:k=>delete obj[k]});Object.defineProperty(window,'localStorage',{value:store(data)});Object.defineProperty(window,'sessionStorage',{value:store({})});}''',data);page.add_script_tag(content=(web/'theme.js').read_text());page.add_script_tag(content=(web/'netcode.js').read_text());page.add_script_tag(content=js);page.wait_for_function("window.__test&&leqra.version==='4.32.0'")
def tap(page,code):
 page.evaluate("c=>window.dispatchEvent(new KeyboardEvent('keydown',{code:c,bubbles:true}))",code);page.wait_for_timeout(45);page.evaluate("c=>window.dispatchEvent(new KeyboardEvent('keyup',{code:c,bubbles:true}))",code);page.wait_for_timeout(90)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 c=b.new_context(viewport={'width':390,'height':844},has_touch=True,is_mobile=True);p=c.new_page();setup(p,{'leqra.muted':'1'});check(p.evaluate("leqra.getState().rules.mapSize")=='compact','Fresh mobile room defaults to Compact 7×7');c.close()
 saved={'version':1,'rules':{'mode':'elimination','teamMode':'ffa','teamNames':['Team 1','Team 2','Team 3','Team 4'],'teamColors':[0,1,2,3],'mapSize':'large','scoreTarget':5,'timeLimit':75,'respawnSeconds':3,'pickupRate':'superfast','friendlyFire':False,'weapons':['rapid','scatter','shield','homing','grenade','speed','laser','scope','cannon','ghost']}}
 c=b.new_context(viewport={'width':390,'height':844},has_touch=True,is_mobile=True);p=c.new_page();setup(p,{'leqra.muted':'1','leqra.roomRules.v1':json.dumps(saved)});check(p.evaluate("leqra.getState().rules.mapSize")=='large','Saved mobile maze choice overrides Compact default');c.close()
 c=b.new_context(viewport={'width':1200,'height':900});p=c.new_page();setup(p,{'leqra.muted':'1'});p.locator('#startRoomBtn').click();p.wait_for_function("leqra.getState().phase==='playing'")
 for code,label in [('KeyC','C'),('Enter','Enter')]:
  p.wait_for_timeout(950);p.evaluate('__test.clearBullets()');tap(p,code);owners=p.evaluate('__test.bullets.map(b=>b.owner)');check(0 in owners,f'Single-player {label} fires Player 1')
 p.evaluate('__test.createLocalRoom()');p.locator('#addLocalBtn').click();second=p.evaluate("leqra.getState().room.players.find(p=>p.kind==='local').id");p.locator('#startRoomBtn').click();p.wait_for_function("leqra.getState().phase==='playing'")
 p.wait_for_timeout(950);p.evaluate('__test.clearBullets()');tap(p,'KeyC');owners=p.evaluate('__test.bullets.map(b=>b.owner)');check(0 in owners and second not in owners,'Two-player C fires Player 1 only')
 p.wait_for_timeout(950);p.evaluate('__test.clearBullets()');tap(p,'Enter');owners=p.evaluate('__test.bullets.map(b=>b.owner)');check(second in owners and 0 not in owners,'Two-player Enter fires Player 2 only')
 p.locator('#roomBtn').click();p.wait_for_timeout(50);manual=p.locator('#manualContent').inner_text();check('C' in manual and 'ENTER' in manual,'Controls help displays supplemental fire keys')
 check(not errors,'No uncaught browser errors: '+str(errors));c.close();b.close()
(out/'results.json').write_text(json.dumps({'version':'4.32.0','passed':len(checks),'checks':checks,'errors':errors},indent=2));print('TOTAL',len(checks))

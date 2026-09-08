"""v4.22 focused UI, auto-save, integrated-chat and Ghost regression checks."""
import json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1];web=root/'web';out=root/'tests/results/v4.22-polish';out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label):
 assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':1200,'height':900});p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={};const st={getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]};Object.defineProperty(window,'localStorage',{value:st});Object.defineProperty(window,'sessionStorage',{value:st});}""")
 p.add_script_tag(content=(web/'theme.js').read_text());p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.28.0'")
 # Callsign is save-on-blur and there are no explicit Save buttons.
 check(p.locator('#roomCallsignForm button').count()==0 and p.locator('#menuCallsignForm button').count()==0,'Callsign editors no longer require explicit Save buttons')
 p.locator('#roomCallsign').fill('Blur Pilot');p.locator('#roomTitle').click();p.wait_for_function("leqra.getState().room.players.some(p=>p.name==='Blur Pilot')")
 check(True,'Local callsign saves automatically when the field loses focus')
 # Join/Create UI is intentionally one action because Join auto-creates missing rooms.
 p.locator('#joinOtherBtn').click();check(p.locator('#joinRoomBtn').count()==1 and p.locator('#createRoomBtn').count()==0,'Join another room exposes one Join action and no redundant Create Room button');p.locator('#onlineBackBtn').click()
 # Online room rename is also buttonless in shipped markup.
 check(p.locator('#roomCodeEditor button').count()==0 and 'Enter or when you leave' in p.locator('#roomCodeEditor').inner_text(),'Online room code editor is auto-save only')
 # Rules/presets/controls dropdown arrows reserve more space on the right.
 p.locator('#roomRulesBtn').click();p.wait_for_function("document.querySelector('#rulesDialog').open")
 style=p.locator('#rulesDialog select').first.evaluate("e=>({pad:parseFloat(getComputedStyle(e).paddingRight),pos:getComputedStyle(e).backgroundPosition})")
 check(style['pad']>=44 and ('25px' in style['pos'] or '19px' in style['pos']),'Feature-menu dropdown arrows have extra right-side spacing')
 p.locator('#rulesDialog .dialog-close').click()
 # Integrated chat has one header button and one compact outgoing-opponent toggle.
 check(p.locator('#enemyChatBtn').count()==0 and p.locator('#chatBtn').count()==1,'Chat uses one integrated header button')
 check(p.locator('#chatOpponentToggle').count()==1 and p.locator('#chatTargetSwitch button').count()==0,'Opponent sending uses a compact in-chat toggle rather than a second chat button')
 # Ghost overlap through a wall is detected as wall-separated, so tank separation cannot pull across it.
 world={'width':1008,'height':840,'cols':12,'rows':10,'walls':[{'x':-4,'y':-4,'w':1016,'h':8},{'x':-4,'y':836,'w':1016,'h':8},{'x':-4,'y':-4,'w':8,'h':848},{'x':1004,'y':-4,'w':8,'h':848},{'x':248,'y':-4,'w':8,'h':848}]}
 p.evaluate('(w)=>__test.setWorld(w)',world);check(p.evaluate('__test.wallBetweenCenters(242,420,31,0)') is True,'Ghost overlap across an interior wall is recognized as wall-separated')
 check(not errors,'No uncaught browser errors: '+str(errors));p.screenshot(path=str(out/'v4.22-ui.png'));c.close();b.close()
report={'version':'4.28.0','passed':len(checks),'checks':checks,'errors':errors};(out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))

"""v4.7 isolated-browser regression: local-room rules persist across reload-equivalent loads."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/local-rules47');a=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[];contexts=[]
def check(ok,label): assert ok,label; checks.append(label); print('PASS',label,flush=True)
def load(browser,store=None):
    c=browser.new_context(viewport={'width':1100,'height':820},color_scheme='dark');contexts.append(c);p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
    p.evaluate('''a=>{window.__location=new URL('https://leqra.test/?test=1');window.__history={state:null,replaceState(){}};window.__store=a.store||{};Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.__store[k]??null,setItem:(k,v)=>window.__store[k]=String(v),removeItem:k=>delete window.__store[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}''',{'store':store or {}})
    for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
    p.add_script_tag(content=js);p.wait_for_function('window.__test && leqra.version==="4.7.0"');return p

def state(p): return p.evaluate('leqra.getState()')

with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
    try:
        p=load(browser,{'leqra.name':'PILOT','leqra.muted':'1'})
        custom={'mode':'ctf','teamMode':'teams','teamNames':['NEON WOLVES','ORBIT','COBALT CREW','NIGHT SHIFT'],'teamColors':[7,5,1,3],'mapSize':'giant','scoreTarget':9,'timeLimit':333,'respawnSeconds':7,'pickupRate':'slow','friendlyFire':True,'weapons':['shield','speed','laser','scope','ghost']}
        p.evaluate('(r)=>__test.setLocalRules(r)',custom)
        stored=p.evaluate("JSON.parse(__store['leqra.roomRules.v1'])")
        check(stored['version']==1 and stored['rules']==custom,'applied local rules are written to versioned localStorage')
        store=p.evaluate('({...__store})');p.close()
        p=load(browser,store)
        check(state(p)['rules']==custom,'map, teams, names/colors and match rules restore after reload')
        room=state(p)['room'];check(room['players'][0]['team']==1 and all(x['team']==2 for x in room['players'][1:]),'restored Teams rules build a valid default local lineup')
        p.locator('#roomRulesBtn').click();check(p.locator('#rule-mapSize').input_value()=='giant' and p.locator('#rule-teamName1').input_value()=='NEON WOLVES','restored values populate Rules & Mode controls');p.locator('[data-close-dialog="rulesDialog"]').click()
        preset={**custom,'mode':'koth','teamMode':'ffa','mapSize':'compact','scoreTarget':44,'timeLimit':222,'respawnSeconds':4,'pickupRate':'superfast','friendlyFire':False,'teamNames':['A','B','C','D'],'teamColors':[0,1,2,3],'weapons':['rapid','scatter']}
        p.evaluate('(r)=>__test.applyLocalPreset({rules:r,roster:[{kind:"human",name:"PILOT",team:0}]})',preset)
        store=p.evaluate('({...__store})');p.close();p=load(browser,store)
        check(state(p)['rules']==preset,'loading a preset updates the automatically restored current rules')
        store=p.evaluate('({...__store})');store['leqra.roomRules.v1']='{bad json';p.close();p=load(browser,store)
        fallback=state(p)['rules'];check(fallback['mapSize']=='large' and fallback['mode']=='elimination' and fallback['teamMode']=='ffa','corrupt stored rules safely fall back to defaults')
        check(not errors,'no uncaught browser errors')
        p.screenshot(path=str(out/'restored-room.png'))
    finally:
        for c in contexts:
            try:c.close()
            except:pass
        browser.close()
report={'version':'4.7.0','passed':len(checks),'checks':checks,'errors':errors};(out/'results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

"""Focused v3.7.1 rendering regression; run with Python Playwright + Chromium.
Uses the shipped scripts with synthetic Location/storage for explicit test mode.
No game logic is replaced and no network service is needed for this visual test.
"""
import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--browser', default='/usr/bin/chromium')
parser.add_argument('--output', default='test-output/flag-labels')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
web = root / 'web'
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
checks, errors = [], []

def check(condition, label):
    if not condition:
        raise AssertionError(label)
    checks.append(label)
    print('PASS', label, flush=True)

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True, executable_path=args.browser)
    try:
        for width, height in [(1365, 950), (390, 844), (320, 568), (844, 390)]:
            mobile = width < 760 or height < 620
            context = browser.new_context(viewport={'width': width, 'height': height},
                is_mobile=mobile, has_touch=mobile, device_scale_factor=2 if mobile else 1)
            try:
                page = context.new_page()
                page.on('pageerror', lambda e: errors.append(str(e)))
                html = re.sub(r'<link[^>]*>', '', (web / 'index.html').read_text())
                html = re.sub(r'<script src="[^"]+" defer></script>', '', html)
                html = html.replace('</head>', '<style>'+(web/'style.css').read_text()+'</style></head>')
                page.set_content(html)
                page.evaluate('''()=>{
                    window.__location=new URL('http://game.test/?test=1');
                    const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,
                        setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});
                    Object.defineProperty(window,'localStorage',{value:store({'leqra.name':'PILOT','leqra.muted':'1'})});
                    Object.defineProperty(window,'sessionStorage',{value:store({})});
                }''')
                js = (web / 'game.js').read_text().replace('(() => {', '((location) => {', 1)
                i = js.rfind('})();')
                assert i >= 0
                js = js[:i] + '})(window.__location);' + js[i+5:]
                page.add_script_tag(content=(web/'netcode.js').read_text())
                page.add_script_tag(content=js)
                page.wait_for_function('window.__test && window.leqra')
                page.evaluate('''()=>{
                    const T=__test;
                    T.applyLocalPreset({rules:{...T.defaultRoomRules(),mode:'ctf',teamMode:'teams',
                        pickupRate:'off',timeLimit:600,scoreTarget:3,
                        teamNames:['Aurora','Red Foxes','Tidal Guard','Violet Squad']},
                        roster:[{kind:'human',name:'PILOT',team:1},
                            {kind:'local',name:'PLAYER TWO',team:1},
                            {kind:'bot',name:'RUST',difficulty:'normal',team:2},
                            {kind:'bot',name:'VAPOR',difficulty:'normal',team:2}]});
                }''')
                page.locator('#startRoomBtn').click()
                page.evaluate('''()=>{
                    const T=__test;T.setPhase('paused');T.clearBullets();
                    for(const t of T.tanks){t.invulnerable=0;t.shield=0;t.speedTime=0;}
                    T.updateHUD(true);
                }''')
                for status in ['home', 'dropped', 'carried']:
                    result = page.evaluate('''status=>{
                        const T=__test,o=T.localObjectives,w=leqra.getState().world;
                        for(let i=0;i<o.flags.length;i++){
                            const f=o.flags[i];f.home=status==='home';f.carrier=-1;
                            f.returnIn=status==='dropped'?7:0;
                            f.x=f.home?f.homeX:w.width*(i===0?.32:.68);
                            f.y=f.home?f.homeY:w.height*.52;
                            if(status==='carried'){
                                const t=T.tanks.find(t=>t.team!==f.team);
                                t.x=w.width*(i===0?.32:.68);t.y=w.height*.52;
                                f.carrier=t.id;f.x=t.x;f.y=t.y;
                            }
                        }
                        T.updateHUD(true);
                        const before=JSON.stringify(o),c=document.querySelector('#arena').getContext('2d');
                        const oldText=c.fillText,oldFill=c.fill;
                        let text=[],fills=0;
                        c.fillText=function(s,...args){text.push(String(s));return oldText.call(this,s,...args)};
                        c.fill=function(...args){fills++;return oldFill.apply(this,args)};
                        let flagText,flagFills,frameText;
                        try {
                            T.drawFlags();flagText=text.slice();flagFills=fills;text=[];
                            T.render();frameText=text.slice();
                        } finally {c.fillText=oldText;c.fill=oldFill;}
                        const r=document.querySelector('#arenaWrap').getBoundingClientRect();
                        return {flagText,flagFills,frameText,count:o.flags.length,
                            unchanged:before===JSON.stringify(o),
                            objective:document.querySelector('#objectiveStatus').textContent,
                            size:[r.width,r.height],overflow:document.documentElement.scrollWidth>innerWidth};
                    }''', status)
                    tag = f'{status} / {width}x{height}'
                    check(result['flagText'] == ['1', '2'], 'Only numbered pennants, no flag captions: '+tag)
                    check(result['flagFills'] == 2*result['count'], 'No extra caption backing strips: '+tag)
                    check(not any(re.search(r'\b(?:BASE|FLAG|CARRIED|DROPPED)\b', t) for t in result['frameText']),
                          'No base or status text drawn beneath flags in full frame: '+tag)
                    check(result['unchanged'], 'Rendering leaves objective state untouched: '+tag)
                    expected = {'home':'HOME','dropped':'DROPPED','carried':'TAKEN'}[status]
                    check(expected in result['objective'] and 'Aurora' in result['objective'],
                          'Top objective status retained: '+tag)
                    check(not result['overflow'] and min(result['size'])>0, 'Layout fits viewport: '+tag)
                    if status == 'home':
                        initial_size=result['size']
                    else:
                        check(result['size']==initial_size, 'Flag state does not resize arena: '+tag)
                    page.screenshot(path=str(out/f'{status}-{width}x{height}.png'))
                # The original layering check: the marker must not obscure a hull.
                overlap = page.evaluate('''()=>{
                    const T=__test,o=T.localObjectives,f=o.flags[0],t=T.tanks[0],v=T.view,w=leqra.getState().world;
                    const clamp=(x,a,b)=>Math.max(a,Math.min(b,x)),z=Math.max(1.35,1/v.scale);
                    f.home=true;f.carrier=-1;f.x=f.homeX;f.y=f.homeY;
                    t.x=clamp(f.x,40*z,w.width-40*z);t.y=clamp(f.y-12*z,26*z,w.height-36*z);
                    t.angle=0;t.recoil=0;t.shield=t.speedTime=t.invulnerable=0;
                    const cv=document.querySelector('#arena'),c=cv.getContext('2d'),d=cv.width/v.cssW;
                    const crop=()=>Array.from(c.getImageData(Math.round((v.offsetX+(t.x-10)*v.scale)*d),
                        Math.round((v.offsetY+(t.y-5)*v.scale)*d),Math.max(1,Math.floor(18*v.scale*d)),
                        Math.max(1,Math.floor(10*v.scale*d))).data);
                    T.render();const a=crop(),flags=o.flags;o.flags=[];T.render();const b=crop();o.flags=flags;T.render();
                    return a.every((n,i)=>n===b[i]);
                }''')
                check(overlap,'Flags still render behind tank hulls: '+str((width,height)))
            finally:
                context.close()
        check(not errors, 'No JavaScript page errors')
        report={'version':'3.7.1','passed':len(checks),'checks':checks,'errors':errors,
            'limits':'Chromium desktop/mobile emulation with injected assets and synthetic Location/storage. No physical-device or public-host testing.'}
        (out/'results.json').write_text(json.dumps(report,indent=2))
        print('TOTAL',len(checks))
    finally:
        browser.close()

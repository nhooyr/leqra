"""v3.7.2 defaults, preference persistence, spawn timing and mobile UI regression.
Optional: Python Playwright + Chromium. Uses the shipped scripts and deterministic
simulation stepping; only URL/storage/audio-call observation are test adapters.
"""
import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--browser', default='/usr/bin/chromium')
parser.add_argument('--output', default='test-output/defaults372')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
web = root/'web'
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
checks, errors = [], []

def check(value, label):
    assert value, label
    checks.append(label)
    print('PASS', label, flush=True)

html = re.sub(r'<link[^>]*>', '', (web/'index.html').read_text())
html = re.sub(r'<script src="[^"]+" defer></script>', '', html)
html = html.replace('</head>', '<style>'+(web/'style.css').read_text()+'</style></head>')
js = (web/'game.js').read_text().replace('(() => {', '((location) => {', 1)
i = js.rfind('})();')
assert i >= 0
js = js[:i] + '})(window.__location);' + js[i+5:]

def load(context, storage=None, broken=False):
    p = context.new_page()
    p.on('pageerror', lambda e: errors.append(str(e)))
    p.set_content(html)
    p.evaluate('''({data,broken})=>{
        window.__location=new URL('http://game.test/?test=1');
        window.__store=data;window.__oscillators=0;
        const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,
            setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
        Object.defineProperty(window,'localStorage',{value:broken?{
            getItem(){throw Error('Storage blocked');},setItem(){throw Error('Storage blocked');}
        }:store(data)});
        Object.defineProperty(window,'sessionStorage',{value:store({})});
        window.requestAnimationFrame=()=>0;
        const A=window.AudioContext||window.webkitAudioContext;
        if(A){const create=A.prototype.createOscillator;A.prototype.createOscillator=function(){
            window.__oscillators++;return create.call(this);
        };}
    }''', {'data': storage or {}, 'broken': broken})
    p.add_script_tag(content=(web/'netcode.js').read_text())
    p.add_script_tag(content=js)
    p.wait_for_function('window.leqra && window.__test')
    return p

def close(p, kind):
    p.locator(f'[data-close-dialog="{kind}Dialog"]').click()

def controls(p):
    p.locator('#roomControlsBtn').click()

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True, executable_path=args.browser)
    try:
        ctx = browser.new_context(viewport={'width':1365,'height':950})
        p = load(ctx)
        check(p.evaluate('leqra.version')=='3.7.2', 'Browser version 3.7.2')
        check(p.evaluate('leqra.getState().rules.pickupRate')=='superfast', 'Fresh local room defaults to Super fast')
        controls(p)
        check(p.locator('#missileAudio').is_checked(), 'Missile warning sound checked by default')
        check(p.locator('#missileVisuals').is_checked(), 'Directional warnings still default on')
        p.screenshot(path=str(out/'settings-desktop.png'))
        p.locator('#missileAudio').uncheck()
        store = p.evaluate('__store')
        check(json.loads(store['leqra.feedback.v1'])['audio'] is False, 'Turning warning sound off persists')
        close(p, 'controls')
        p2 = load(ctx, store)
        controls(p2)
        check(not p2.locator('#missileAudio').is_checked(), 'Explicit saved sound-off remains off after reload')
        p2.locator('#missileAudio').check()
        enabled_store=p2.evaluate('__store')
        p2.close()
        p2=load(ctx, enabled_store)
        controls(p2)
        check(p2.locator('#missileAudio').is_checked(), 'Explicit saved sound-on persists after reload')
        p2.close()
        for data,label in [({},'empty settings'),({'visual':False,'fps':True},'missing audio field')]:
            p2=load(ctx, {'leqra.feedback.v1':json.dumps(data)})
            controls(p2)
            check(p2.locator('#missileAudio').is_checked(),'Sound defaults on with '+label)
            if 'visual' in data:
                check(not p2.locator('#missileVisuals').is_checked() and p2.locator('#showFPS').is_checked(),'Other saved feedback preferences preserved')
            p2.close()
        for raw in ['invalid JSON','null']:
            p2=load(ctx, {'leqra.feedback.v1':raw})
            controls(p2)
            check(p2.locator('#missileAudio').is_checked(),'Sound defaults on after '+raw)
            p2.close()
        p2=load(ctx, broken=True)
        controls(p2)
        check(p2.locator('#missileAudio').is_checked(),'Sound defaults on when storage is unavailable')
        p2.close()

        # A real user Start click creates/resumes the native AudioContext. Count
        # scheduled oscillators rather than claiming physical speaker validation.
        p2=load(ctx)
        p2.locator('#startRoomBtn').click()
        p2.wait_for_timeout(100)
        sound=p2.evaluate('''()=>{
            const T=__test;T.setPhase('playing');T.clearBullets();
            T.addBullet({id:900,owner:1,kind:'homing',target:0,dead:false,x:200,y:200});
            const before=__oscillators;T.updateCombatFeedback(true);
            return {tones:__oscillators-before,warning:!document.querySelector('#missileWarning1').hidden};
        }''')
        check(sound['warning'], 'Actual missile lock displays the existing warning')
        check(sound['tones']==2, 'Default warning schedules the two-tone lock sound')
        p2.close()
        for data,label in [({'leqra.muted':'1'},'global mute'),({'leqra.feedback.v1':'{"audio":false}'},'warning disabled')]:
            p2=load(ctx,data);p2.locator('#startRoomBtn').click();p2.wait_for_timeout(80)
            silent=p2.evaluate('''()=>{const T=__test;T.setPhase('playing');T.clearBullets();T.addBullet({id:900,owner:1,kind:'homing',target:0,dead:false,x:200,y:200});const before=__oscillators;T.updateCombatFeedback(true);return __oscillators-before;}''')
            check(silent==0,'No lock sound when '+label)
            p2.close()

        p.locator('#roomRulesBtn').click()
        options=p.locator('#rule-pickupRate option').evaluate_all('(xs)=>xs.map(x=>({value:x.value,text:x.textContent}))')
        check([x['value'] for x in options]==['superfast','fast','normal','slow','off'],'Selector contains the new tier and all four existing choices')
        check('1–2s' in options[0]['text'] and 'default' in options[0]['text'],'New tier has clear interval/default label')
        check(p.locator('#rule-pickupRate').input_value()=='superfast','Rules editor preselects Super fast')
        p.screenshot(path=str(out/'rules-desktop.png'))
        for rate in ['fast','normal','slow','off','superfast']:
            p.locator('#rule-pickupRate').select_option(rate)
            p.locator('#applyRulesBtn').click()
            check(p.evaluate('leqra.getState().rules.pickupRate')==rate,'Host can apply '+rate)
            p.locator('#roomRulesBtn').click()
        close(p,'rules')

        # Use the shipping saved-preset controls, not a surrogate data model.
        p.locator('#roomPresetsBtn').click()
        p.locator('#presetName').fill('Super fast setup')
        p.locator('#savePresetBtn').click()
        saved=p.evaluate('__store')
        check(json.loads(saved['leqra.presets.v1'])['items'][0]['rules']['pickupRate']=='superfast','Custom preset saves Super fast')
        p2=load(ctx,saved);p2.locator('#roomPresetsBtn').click();p2.locator('#presetSelect').select_option('saved:0');p2.locator('#loadPresetBtn').click()
        check(p2.evaluate('leqra.getState().rules.pickupRate')=='superfast','Saved Super fast preset loads after reload')
        p2.close()
        legacy=json.loads(saved['leqra.presets.v1']);legacy['items'][0]['rules']['pickupRate']='fast'
        saved['leqra.presets.v1']=json.dumps(legacy)
        p2=load(ctx,saved);p2.locator('#roomPresetsBtn').click();p2.locator('#presetSelect').select_option('saved:0');p2.locator('#loadPresetBtn').click()
        check(p2.evaluate('leqra.getState().rules.pickupRate')=='fast','Older preset keeps its explicit Fast frequency')
        p2.close();close(p,'presets')
        for index in range(5):
            p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('builtin:'+str(index));p.locator('#loadPresetBtn').click()
            check(p.evaluate('leqra.getState().rules.pickupRate')=='superfast','Built-in preset '+str(index)+' inherits new default')

        for mode in ['elimination','ctf','koth']:
            for rate,lo,hi in [('superfast',1,2),('fast',2,3.5),('normal',4,6),('slow',7,10),('off',2,3.5)]:
                observed=p.evaluate('''({mode,rate,lo,hi})=>{
                    const T=__test;T.setPhase('menu');
                    T.setLocalRules({...T.defaultRoomRules(),mode,teamMode:'teams',pickupRate:rate,weapons:['laser']});
                    T.startRound();T.setPhase('playing');
                    for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=999;}
                    const initial=T.pickups.length;
                    const beforeSteps=Math.round(lo*120)-1;
                    for(let i=0;i<beforeSteps;i++)T.update(1/120);
                    const before=T.pickups.length;
                    for(let i=0;i<2;i++)T.update(1/120);
                    const after=T.pickups.length;
                    const delays=[];
                    if(rate!=='off')for(let n=0;n<6;n++){
                        T.pickups.length=0;let elapsed=0;
                        while(!T.pickups.length&&elapsed<hi+.1){T.update(1/120);elapsed+=1/120;}
                        delays.push(elapsed);
                    }
                    for(let i=0;i<100;i++)T.spawnPower();
                    const result={initial,before,after,delays,cap:T.pickups.length,onlyLaser:T.pickups.every(x=>x.type==='laser')};
                    T.setPhase('menu');return result;
                }''',{'mode':mode,'rate':rate,'lo':lo,'hi':hi})
                check(observed['initial']==(0 if rate=='off' else 2) and observed['before']==observed['initial'] and observed['after']==(0 if rate=='off' else 3),mode+' '+rate+' starting count and first-delay boundary')
                check(all(lo-.02<=v<=hi+.02 for v in observed['delays']) and observed['cap']==(0 if rate=='off' else 5) and observed['onlyLaser'],mode+' '+rate+' repeated interval, weapon filter and five-pickup cap')
        ctx.close()

        for width,height in [(320,568),(390,844),(844,390)]:
            c=browser.new_context(viewport={'width':width,'height':height},is_mobile=True,has_touch=True,device_scale_factor=2)
            p=load(c);controls(p)
            check(p.locator('#missileAudio').is_checked(),f'Mobile sound default {width}x{height}')
            close(p,'controls');p.locator('#roomRulesBtn').click()
            p.locator('#rule-pickupRate').scroll_into_view_if_needed()
            check(p.locator('#rule-pickupRate').input_value()=='superfast',f'Mobile frequency default {width}x{height}')
            check(p.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),f'No horizontal page overflow {width}x{height}')
            check(p.evaluate('''()=>{const e=document.querySelector('#rule-pickupRate'),s=getComputedStyle(e),c=document.createElement('canvas').getContext('2d');c.font=s.font;return c.measureText(e.selectedOptions[0].textContent).width<=e.clientWidth-parseFloat(s.paddingLeft)-parseFloat(s.paddingRight)-24;}'''),f'Full interval label fits {width}x{height}')
            p.screenshot(path=str(out/f'rules-{width}x{height}.png'))
            close(p,'rules');c.close()
        check(not errors,'No uncaught browser errors')
        report={'version':'3.7.2','passed':len(checks),'checks':checks,'errors':errors,'limits':'Chromium desktop/mobile emulation; exact assets, synthetic URL/storage, manual simulation stepping. Native AudioContext scheduling observed, not physical speaker validation.'}
        (out/'results.json').write_text(json.dumps(report,indent=2))
        print('TOTAL',len(checks))
    finally:
        browser.close()

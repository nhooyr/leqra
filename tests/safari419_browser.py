"""v4.19 Safari/WebKit compatibility regression checks.

Chromium is used as a DOM/JS host with Safari/iOS identities because this build
container cannot install Playwright WebKit. These checks validate the shipped
Safari code/CSS paths, touch classification and release fallbacks; physical
Safari is still listed separately in the release limits.
"""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

root=Path(__file__).resolve().parents[1]; web=root/'web'
parser=argparse.ArgumentParser(); parser.add_argument('--output',default=str(root/'tests/results/v4.19-safari')); args=parser.parse_args()
out=Path(args.output); out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label):
    assert ok,label;checks.append(label);print('PASS',label,flush=True)
def install(page,platform,max_touch):
    page.set_content(html)
    page.evaluate("""a=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const store={getItem(){return null},setItem(){},removeItem(){}};Object.defineProperty(window,'localStorage',{value:store});Object.defineProperty(window,'sessionStorage',{value:store});window.__nativeAudioPlays=0;window.Audio=class{constructor(){this.src='';this.volume=1;this.currentTime=0;this.preload='';this.playsInline=false;this.dataset={};}setAttribute(){}pause(){}load(){}play(){window.__nativeAudioPlays++;return Promise.resolve();}};window.AudioContext=undefined;window.webkitAudioContext=undefined;try{Object.defineProperty(navigator,'platform',{value:a.platform,configurable:true});Object.defineProperty(navigator,'maxTouchPoints',{value:a.maxTouch,configurable:true});Object.defineProperty(navigator,'userAgentData',{value:undefined,configurable:true});}catch(_){}}""",{'platform':platform,'maxTouch':max_touch})
    for f in ['theme.js','netcode.js']:page.add_script_tag(content=(web/f).read_text())
    page.add_script_tag(content=js);page.wait_for_function("window.__test&&leqra.version==='4.23.1'")

safari_mac='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
safari_phone='Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'
safari_ipad_desktop='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/605.1.15'
with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
    # Desktop Safari identity.
    c=browser.new_context(viewport={'width':1365,'height':950},device_scale_factor=2,user_agent=safari_mac,color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append('desktop: '+str(e)));install(p,'MacIntel',0)
    plat=p.evaluate('__test.platform');check(plat=={'webkit':True,'safari':True,'ios':False},'desktop Safari selects the WebKit/Safari optimization path')
    check(p.locator('body').evaluate("e=>e.classList.contains('webkit-engine')&&e.classList.contains('safari-browser')"),'desktop Safari receives WebKit CSS performance class')
    check(p.locator('#browserNotice').count()==1 and 'Chrome or Firefox' in p.locator('#browserNotice').inner_text(),'desktop Safari recommends Chrome or Firefox')
    before=p.evaluate('__nativeAudioPlays');p.locator('#soundBtn').dispatch_event('pointerdown');p.evaluate('__test.chatNotificationSound()');p.wait_for_timeout(20);after=p.evaluate('__nativeAudioPlays');check(after>before,'desktop Safari sound uses the native-audio fallback even without a usable WebAudio context')
    ratio=p.evaluate('__test.renderPixelRatio(1200,700)');check(1<=ratio<=1.75,'desktop Safari caps adaptive Canvas pixel density at 1.75x')
    blur=p.evaluate("getComputedStyle(document.querySelector('.overlay')).webkitBackdropFilter||getComputedStyle(document.querySelector('.overlay')).backdropFilter")
    check(blur in ('none',''),'Safari path disables full-arena backdrop blur')
    # Fractional geometry should not churn a one-pixel backing-store resize.
    dims=p.evaluate("""()=>{const w=document.querySelector('#arenaWrap'),orig=w.getBoundingClientRect;let width=800,height=500;w.getBoundingClientRect=()=>({width,height,left:0,top:0,right:width,bottom:height,x:0,y:0});__test.resize();const a=[arena.width,arena.height];width=800.45;__test.resize();const b=[arena.width,arena.height];w.getBoundingClientRect=orig;return{a,b};}""")
    check(dims['a']==dims['b'],'fractional WebKit layout jitter does not reallocate Canvas for a 1px wobble')
    p.screenshot(path=str(out/'safari-desktop-path.png'));c.close()

    # iPhone Safari identity at DPR 3: touch UI, lower pixel budget, release fallback.
    c=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=3,user_agent=safari_phone,is_mobile=True,has_touch=True,color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append('iphone: '+str(e)));install(p,'iPhone',5);p.wait_for_timeout(40)
    plat=p.evaluate('__test.platform');check(plat=={'webkit':True,'safari':True,'ios':True},'iPhone Safari selects iOS WebKit path')
    check(p.locator('#browserNotice').count()==0,'iPhone Safari does not show the desktop browser recommendation')
    before=p.evaluate('__nativeAudioPlays');p.locator('#soundBtn').dispatch_event('touchstart');p.evaluate('__test.pickupSound ? __test.pickupSound() : __test.chatNotificationSound()');p.wait_for_timeout(20);check(p.evaluate('__nativeAudioPlays')>before,'iPhone Safari native-audio fallback survives touch-unlock flow')
    st=p.evaluate('leqra.getState()');check(st['touchUI'] is True,'iPhone Safari receives touch controls');p.locator('#startRoomBtn').click();p.wait_for_timeout(80)
    ratio=p.evaluate('__test.renderPixelRatio(390,650)');check(1<=ratio<=1.5,'iPhone Safari caps Canvas density at 1.5x instead of native 3x')
    check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'iPhone Safari path has no horizontal page overflow')
    font=p.evaluate("getComputedStyle(document.querySelector('#presetName')).fontSize")
    check(float(font.removesuffix('px'))>=16,'iPhone Safari editable controls stay at 16px to prevent focus auto-zoom')
    check(p.locator('canvas[data-power-icon]').first.get_attribute('width') is not None and int(p.locator('canvas[data-power-icon]').first.get_attribute('width'))<=52,'Safari power-up legend caps icon backing resolution at 2x')
    reads=p.evaluate("""()=>{const base=stickBase,zone=stickZone,orig=base.getBoundingClientRect.bind(base);let reads=0;base.getBoundingClientRect=()=>{reads++;return orig()};const r=orig(),id=66;zone.dispatchEvent(new PointerEvent('pointerdown',{pointerId:id,clientX:r.left+r.width*.55,clientY:r.top+r.height*.55,bubbles:true,cancelable:true,pointerType:'touch'}));for(let i=0;i<20;i++)zone.dispatchEvent(new PointerEvent('pointermove',{pointerId:id,clientX:r.left+r.width*(.45+i*.01),clientY:r.top+r.height*.55,bubbles:true,cancelable:true,pointerType:'touch'}));window.dispatchEvent(new PointerEvent('pointerup',{pointerId:id,bubbles:true,cancelable:true,pointerType:'touch'}));base.getBoundingClientRect=orig;return reads;}""")
    check(reads==1,'Safari joystick caches geometry instead of forcing layout on every pointer move')
    # Pointer capture may be lost in WebKit; window-level release must still clear controls.
    reset=p.evaluate("""()=>{const z=stickZone,b=z.getBoundingClientRect(),id=77;z.setPointerCapture=()=>{throw new Error('simulated WebKit capture loss')};z.dispatchEvent(new PointerEvent('pointerdown',{pointerId:id,clientX:b.left+b.width*.75,clientY:b.top+b.height*.3,bubbles:true,cancelable:true,pointerType:'touch'}));const moved=stickKnob.style.transform;window.dispatchEvent(new PointerEvent('pointerup',{pointerId:id,bubbles:true,cancelable:true,pointerType:'touch'}));return{moved,after:stickKnob.style.transform};}""")
    check(reset['moved'] not in ('translate(0,0)','translate(0px, 0px)') and reset['after'] in ('translate(0,0)','translate(0px, 0px)'),'lost pointer capture cannot leave the Safari joystick stuck')
    fire=p.evaluate("""()=>{const id=88;fireBtn.setPointerCapture=()=>{throw new Error('simulated WebKit capture loss')};fireBtn.dispatchEvent(new PointerEvent('pointerdown',{pointerId:id,bubbles:true,cancelable:true,pointerType:'touch'}));const held=fireBtn.classList.contains('held');window.dispatchEvent(new PointerEvent('pointercancel',{pointerId:id,bubbles:true,cancelable:true,pointerType:'touch'}));return{held,after:fireBtn.classList.contains('held')};}""")
    check(fire['held'] and not fire['after'],'lost/cancelled Safari fire pointer cannot leave FIRE held')
    gesture=p.evaluate("""()=>{const e=new Event('gesturestart',{bubbles:true,cancelable:true});touchControls.dispatchEvent(e);return e.defaultPrevented;}""")
    check(gesture,'Safari multi-touch gesture zoom is suppressed over game controls')
    p.screenshot(path=str(out/'safari-iphone-path.png'));c.close()

    # iPhone Safari landscape has very little stable vertical viewport once browser chrome is present.
    c=browser.new_context(viewport={'width':844,'height':390},device_scale_factor=3,user_agent=safari_phone,is_mobile=True,has_touch=True,color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append('iphone-landscape: '+str(e)));install(p,'iPhone',5);p.wait_for_timeout(40)
    st=p.evaluate('leqra.getState()');check(st['touchUI'] is True and st['touchLandscape'] is True,'iPhone Safari landscape selects compact touch-landscape layout')
    p.locator('#startRoomBtn').click();p.wait_for_timeout(80)
    check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),'iPhone Safari landscape has no horizontal page overflow')
    bounds=p.evaluate("()=>{const a=document.querySelector('.arena-shell').getBoundingClientRect(),t=touchControls.getBoundingClientRect();return{arenaRight:a.right,arenaBottom:a.bottom,touchRight:t.right,touchBottom:t.bottom,w:innerWidth,h:innerHeight}}")
    check(bounds['arenaRight']<=bounds['w']+1 and bounds['touchRight']<=bounds['w']+1,'iPhone Safari landscape arena and touch HUD stay within viewport width')
    check(bounds['touchBottom']<=bounds['h']+1,'iPhone Safari landscape touch HUD stays within viewport height')
    p.screenshot(path=str(out/'safari-iphone-landscape-path.png'));c.close()

    # iPadOS can advertise Macintosh + a fine primary pointer when a trackpad is attached.
    c=browser.new_context(viewport={'width':1024,'height':768},device_scale_factor=2,user_agent=safari_ipad_desktop,is_mobile=False,has_touch=False,color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append('ipad: '+str(e)));install(p,'MacIntel',5);p.wait_for_timeout(40)
    plat=p.evaluate('__test.platform');st=p.evaluate('leqra.getState()');
    check(plat['ios'] and plat['webkit'],'Macintosh-style iPadOS Safari is recognized as iOS WebKit')
    check(st['touchUI'] is True,'iPadOS keeps touch controls even when its primary pointer is desktop/fine')
    c.close();browser.close()

check(not errors,'no JavaScript errors in Safari identity paths: '+str(errors))
report={'version':'4.23.1','passed':len(checks),'checks':checks,'errors':errors,'note':'Safari identities executed in Chromium because Playwright WebKit could not be installed in this environment.'}
(out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))

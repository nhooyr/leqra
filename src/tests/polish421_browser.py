"""v4.21 audio-volume and Safari async-audio regression checks."""
import json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1];web=root/'web';out=root/'tests/results/v4.22-audio';out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label):
    assert ok,label;checks.append(label);print('PASS',label,flush=True)
with sync_playwright() as pw:
    b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':1100,'height':820});p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
    p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={};const store={getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]};Object.defineProperty(window,'localStorage',{value:store});Object.defineProperty(window,'sessionStorage',{value:store});window.__stored=d;window.__audioStarts=0;window.__masterLevels=[];class FakeAudioContext{constructor(){this.state='suspended';this.currentTime=0;this.sampleRate=48000;this.destination={};this.gains=0;}resume(){return new Promise(r=>setTimeout(()=>{this.state='running';r();},25));}createGain(){const idx=this.gains++;return{gain:{value:1,setValueAtTime:(v)=>{if(idx===0)window.__masterLevels.push(v)},linearRampToValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){}}}createOscillator(){return{type:'sine',frequency:{setValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){},start(){window.__audioStarts++},stop(){}}}createBuffer(){return{getChannelData(){return new Float32Array(16)}}}createBufferSource(){return{buffer:null,connect(){},start(){window.__audioStarts++}}}createBiquadFilter(){return{type:'',frequency:{value:0},connect(){}}}}window.AudioContext=FakeAudioContext;window.webkitAudioContext=FakeAudioContext;}""")
    p.add_script_tag(content=(web/'theme.js').read_text());p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.35.0'")
    check(p.locator('#masterVolume').input_value()=='50' and p.locator('#masterVolumeValue').inner_text()=='50%','Default/current audio volume is centered at 50%')
    p.evaluate('window.__audioStarts=0;__test.chatNotificationSound()')
    check(p.evaluate('window.__audioStarts')==0,'Suspended Safari-style AudioContext does not falsely report immediate playback')
    p.wait_for_timeout(60)
    check(p.evaluate('window.__audioStarts')>=2 and p.evaluate('__test.audioState')=='running','Queued sound begins after asynchronous AudioContext resume completes')
    p.locator('#roomControlsBtn').click();p.wait_for_function("document.querySelector('#controlsDialog').open")
    p.locator('#masterVolume').evaluate("e=>{e.value='53';e.dispatchEvent(new Event('input',{bubbles:true}))}")
    check(p.locator('#masterVolume').input_value()=='50' and p.evaluate('__test.audioVolume')==50,'Volume slider snaps to the halfway point near 50%')
    p.locator('#masterVolume').evaluate("e=>{e.value='67';e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}))}")
    check(p.locator('#masterVolume').input_value()=='67' and p.locator('#masterVolumeValue').inner_text()=='67%' and p.evaluate("window.__stored['leqra.volume']")=='67','Volume changes live and persist on this device')
    p.evaluate('__test.setAudioVolume(100,false,false)')
    check(abs(p.evaluate('window.__masterLevels.at(-1)')-2)<1e-9,'100% volume scales above the original midpoint while 50% preserves the old level')
    check(not errors,'No uncaught browser errors in audio controls: '+str(errors))
    p.screenshot(path=str(out/'controls-volume.png'));c.close();b.close()
report={'version':'4.35.0','passed':len(checks),'checks':checks,'errors':errors};(out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))

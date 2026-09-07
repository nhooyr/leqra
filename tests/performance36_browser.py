"""Controlled Canvas2D sprite-cache A/B. Not a GPU timer or cross-device FPS promise.
Run: python tests/performance36_browser.py PROJECT_ROOT OUTPUT
"""
import json,re,sys,statistics
from pathlib import Path
from playwright.sync_api import sync_playwright
root=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');p=b.new_page(viewport={'width':1365,'height':950});errors=[];p.on('pageerror',lambda e:errors.append(str(e)))
 web=root/'web';html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
 p.evaluate("window.__location=new URL('http://game.test/?test=1');const store={'leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>store[k]||null,setItem:(k,v)=>store[k]=v,removeItem:k=>delete store[k]}})")
 js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:];p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js)
 p.evaluate("()=>{let seed=360;Math.random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const T=__test;T.setLocalRules({...T.currentRules(),mode:'koth',mapSize:'huge',teamMode:'ffa',timeLimit:600,scoreTarget:300});while(leqra.getState().room.players.length<8)T.addRoomSeat('bot');}")
 p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"');p.evaluate("()=>{__test.setPhase('paused');__test.clearBullets();for(const t of __test.tanks){t.alive=true;t.invulnerable=0;t.speedTime=0;t.shield=0;t.angle=t.id*.51;t.track=2*(t.id%4);}__test.render();}")
 calls=p.evaluate('''()=>{const T=__test,c=document.querySelector('#arena').getContext('2d'),methods=['beginPath','moveTo','lineTo','arc','arcTo','fill','stroke','fillRect','drawImage','measureText'],originals={},result={};let counts={};for(const k of methods){originals[k]=c[k];c[k]=function(...args){counts[k]=(counts[k]||0)+1;return originals[k].apply(this,args)}}for(const on of [false,true]){T.setHullCache(on);T.render();counts={};T.render();result[on?'cached':'vector']={...counts};}for(const k of methods)c[k]=originals[k];return result;}''')
 trials=p.evaluate('''async()=>{const T=__test,out=[];for(const on of [false,true,true,false,false,true,true,false]){T.setHullCache(on);for(let i=0;i<15;i++)T.render();await new Promise(r=>setTimeout(r,40));const n=150,t=performance.now();for(let i=0;i<n;i++)T.render();out.push({cached:on,frames:n,submission_ms:(performance.now()-t)/n});await new Promise(r=>setTimeout(r,80));}return out;}''')
 frames={}
 for on in [False,True]:
  p.evaluate('(v)=>__test.setHullCache(v)',on)
  values=p.evaluate('''()=>new Promise(resolve=>{const intervals=[];let last=0,start=0;function f(t){if(!start)start=t;if(last)intervals.push(t-last);last=t;if(t-start<6000)requestAnimationFrame(f);else resolve(intervals);}requestAnimationFrame(f);})''')
  frames['cached' if on else 'vector']={'frames':len(values),'average_frame_ms':statistics.mean(values),'p95_frame_ms':sorted(values)[int(.95*len(values))],'over_25ms':sum(v>25 for v in values)}
 result={'version':'3.6.0','scenario':'Same frozen 8-tank 14x12 scene, 1365x950 desktop, DPR 1, Chromium headless; only hull-cache switch changes. Both use bounded text-width caching. 8 alternating 150-render batches; synchronous JS/Canvas submission, not GPU completion. Separate 6-second RAF samples.','main_canvas_calls':calls,'trials':trials,'median_submission_ms':{label:statistics.median(t['submission_ms'] for t in trials if t['cached']==on) for label,on in [('vector',False),('cached',True)]},'raf':frames,'cache':p.evaluate('__test.renderStats'),'errors':errors}
 p.screenshot(path=str(out/'eight-tank-cache.png'));(out/'report.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2));b.close()

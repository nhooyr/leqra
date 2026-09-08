"""Usage: python tests/performance35_browser.py PROJECT_ROOT OUTPUT [4|8]. Optional Playwright/Chromium.
Exact assets injected; local simulation only.
"""
import json,sys,time,re
from pathlib import Path
from collections import Counter
from playwright.sync_api import sync_playwright
count=int(sys.argv[3]) if len(sys.argv)>3 else 4
root=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(exist_ok=True,parents=True)
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 p=b.new_page(viewport={'width':1365,'height':950}); errors=[];p.on('pageerror',lambda e:errors.append(str(e)))
 web=root/'web';html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
 p.evaluate("window.__location=new URL('http://game.test/?test=1');const store={};Object.defineProperty(window,'localStorage',{value:{getItem:k=>store[k]||null,setItem:(k,v)=>store[k]=v,removeItem:k=>delete store[k]}});localStorage.setItem('leqra.muted','1');")
 js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
 p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.__test')
 p.evaluate('''count=>{let seed=35;Math.random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const T=__test;T.setLocalRules({...T.currentRules(),mode:'koth',mapSize:'large',teamMode:'ffa',timeLimit:600,scoreTarget:300});while(leqra.getState().room.players.length<count)T.addRoomSeat('bot');}''',count)
 p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"')
 p.evaluate('''()=>{__test.tanks.forEach(t=>t.invulnerable=999);window.__perfFrames=[];window.__mutations=0;let last=0;new MutationObserver(m=>__mutations+=m.length).observe(document.querySelector('.app'),{subtree:true,attributes:true,characterData:true,childList:true});function f(now){if(last)__perfFrames.push(now-last);last=now;requestAnimationFrame(f);}requestAnimationFrame(f);}''')
 c=p.context.new_cdp_session(p);c.send('Profiler.enable');c.send('Profiler.start');p.wait_for_timeout(8000)
 prof=c.send('Profiler.stop')['profile'];(out/'cpu.json').write_text(json.dumps(prof));counts=Counter(prof.get('samples',[]));nodes={n['id']:n for n in prof['nodes']};top=[(nodes[i]['callFrame']['functionName'],nodes[i]['callFrame']['lineNumber']+1,n) for i,n in counts.most_common(20)]
 frames=p.evaluate('__perfFrames');s=sorted(frames);report={'tank_count':count,'map':'12x10','scenario':'Seeded local KOTH; 8 second RAF + mutation + sampled CPU profile; invulnerable tanks (light combat).','frames':len(frames),'average_frame_ms':sum(frames)/len(frames),'p95_frame_ms':s[int(.95*len(s))],'over_25ms':sum(x>25 for x in s),'dom_mutations':p.evaluate('__mutations'),'cpu_top':top,'errors':errors}
 (out/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));b.close()

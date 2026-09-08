"""Browser checks with four independent clients. Optional tooling:
  pip install playwright
  playwright install chromium
  python tests/browser_smoke.py http://localhost:8080
Use --isolated only with TestBrowserFixture (see TESTING.md).
"""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument('url',nargs='?',default='http://localhost:8080')
parser.add_argument('--isolated',action='store_true')
parser.add_argument('--browser',default=None)
parser.add_argument('--output',default='test-output')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]/'web'
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
html=root.joinpath('index.html').read_text()
html=re.sub(r'<link[^>]*>','',html).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+root.joinpath('style.css').read_text()+'</style></head>')
js=root.joinpath('game.js').read_text().replace('(() => {','((location) => {',1)
pos=js.rfind('})();');js=js[:pos]+f'}})(new URL({json.dumps(args.url+"/?test=1")}));'+js[pos+5:]
wrapper="""window.__sockets=[];const RealSocket=window.WebSocket;window.WebSocket=class extends RealSocket{constructor(...args){super(...args);window.__sockets.push(this)}};"""
checks=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
def load(page):
 if args.isolated:
  page.set_content(html);page.evaluate("()=>{"+wrapper+"}");page.add_script_tag(content=root.joinpath('netcode.js').read_text());page.add_script_tag(content=js)
 else:
  page.add_init_script(wrapper);page.goto(args.url+'/?test=1')
 page.wait_for_function('window.leqra')
def state(page):return page.evaluate('leqra.getState()')

with sync_playwright() as pw:
 options={'headless':True}
 if args.browser:options['executable_path']=args.browser
 browser=pw.chromium.launch(**options)
 pages=[];contexts=[];errors=[]
 layouts=[(1365,950,False),(390,844,True),(320,568,True),(844,390,True)]
 for i,(w,h,mobile) in enumerate(layouts):
  context=browser.new_context(viewport={'width':w,'height':h},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1)
  contexts.append(context);page=context.new_page();pages.append(page)
  page.on('pageerror',lambda e:errors.append(str(e)))
  load(page);page.locator('[data-mode=online]').click();page.locator('#pilotName').fill(['HOST','PHONE','POCKET','WIDE'][i])
 pages[0].locator('#createRoomBtn').click();pages[0].wait_for_function('leqra.getState().online?.connected')
 code=state(pages[0])['online']['code']
 for page in pages[1:]:
  page.locator('#joinCode').fill(code);page.locator('#joinRoomBtn').click();page.wait_for_function('leqra.getState().online?.connected')
 for i,page in enumerate(pages):
  page.wait_for_function('leqra.getState().online.players.length===4')
  check(page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'No horizontal overflow: {layouts[i][0]}x{layouts[i][1]}')
  page.screenshot(path=str(out/f'lobby-{layouts[i][0]}x{layouts[i][1]}.png'))
  page.locator('#readyBtn').click()
 pages[0].locator('#startRoomBtn').click()
 for page in pages:page.wait_for_function('leqra.getState().phase==="playing"')
 check(all(len(state(page)['tanks'])==4 for page in pages),'Four browser clients render shared arena')
 check(all(state(page)['world']==state(pages[0])['world'] for page in pages),'Desktop and phones use identical arena dimensions')
 # Real Chromium multi-touch dispatch: two fingers held simultaneously.
 phone=pages[1];cdp=contexts[1].new_cdp_session(phone)
 st=phone.locator('#stickBase').bounding_box();fb=phone.locator('#fireBtn').bounding_box()
 cx=st['x']+st['width']/2;cy=st['y']+st['height']/2
 points=[{'x':cx+32,'y':cy-9,'id':11},{'x':fb['x']+fb['width']/2,'y':fb['y']+fb['height']/2,'id':12}]
 before=state(phone);angle=next(t['angle'] for t in before['tanks'] if t['id']==1)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':points})
 phone.wait_for_timeout(230)
 after=state(phone)
 check(phone.locator('#fireBtn').evaluate('e=>e.classList.contains("held")'),'Touch fire button held while joystick active')
 check(phone.locator('#stickKnob').evaluate('e=>e.style.transform')!='translate(0,0)','Touch joystick receives simultaneous pointer')
 check(abs(next(t['angle'] for t in after['tanks'] if t['id']==1)-angle)>.02,'Touch steering changes server-backed tank heading')
 check(after['bulletCount']>0,'Touch fire creates shared authoritative projectile')
 phone.screenshot(path=str(out/'mobile-controls-active.png'))
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 phone.wait_for_timeout(80)
 check(not phone.locator('#fireBtn').evaluate('e=>e.classList.contains("held")'),'Touch release clears held fire')
 # A genuine socket closure invokes the shipped client's resume flow.
 old=state(pages[3])['online'];oldCount=pages[3].evaluate('__sockets.length')
 pages[3].evaluate('__sockets.at(-1).close(4000,"Test connection drop")')
 pages[3].wait_for_function('n=>__sockets.length>n && leqra.getState().online?.connected',arg=oldCount,timeout=9000)
 current=state(pages[3])['online']
 check(current['id']==old['id'] and current['code']==old['code'],'Browser auto-reconnect preserves room and player')
 # Local menu never pauses the shared match.
 pages[0].locator('#pauseBtn').click();tick=state(pages[0])['online']['serverTick'];pages[0].wait_for_timeout(250)
 check(state(pages[0])['online']['serverTick']>tick,'Opening online menu leaves server match running')
 pages[0].locator('#onlineReturnBtn').click()
 for i,page in enumerate(pages):page.screenshot(path=str(out/f'playing-{layouts[i][0]}x{layouts[i][1]}.png'))
 # Leave online, then exercise both preserved offline modes in the same app.
 pages[0].locator('#pauseBtn').click();pages[0].locator('#onlineLeaveBtn').click()
 check(state(pages[0])['mode']=='solo' and state(pages[0])['phase']=='menu','Leaving online restores offline lobby')
 pages[0].locator('#playBtn').click();pages[0].wait_for_function('leqra.getState().phase==="playing"')
 check(len(state(pages[0])['tanks'])==3,'Solo bot squad still available')
 pages[0].locator('#pauseBtn').click();pages[0].locator('#quitBtn').click();pages[0].locator('[data-mode=duel]').click();pages[0].locator('#playBtn').click();pages[0].wait_for_function('leqra.getState().phase==="playing"')
 check(len(state(pages[0])['tanks'])==2 and state(pages[0])['mode']=='duel','Local two-player mode preserved')
 check(not errors,'No JavaScript runtime errors')
 report={'checks_passed':len(checks),'checks':checks,'javascript_errors':errors,'layouts':layouts,'isolated_assets':args.isolated,'browser_version':browser.version}
 (out/'browser-results.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
 browser.close()

"""Live two-browser smoothing test with ordered synthetic WebSocket delay.

Uses real sockets to a dedicated test server. Delays are injected only by this
harness (not shipped game code). No real packet loss or public WAN is simulated.
Requires optional Playwright; see TESTING.md for the opt-in isolated fixture.
"""
import argparse,json,math,re,statistics,urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument('url',nargs='?',default='http://localhost:8080')
parser.add_argument('--assets',default=str(Path(__file__).resolve().parents[1]/'web'))
parser.add_argument('--isolated',action='store_true')
parser.add_argument('--browser',default=None)
parser.add_argument('--output',default='test-output/network')
parser.add_argument('--motion',choices=['turn','move'],default='turn',help='move requires the opt-in lane fixture')
parser.add_argument('--profile',choices=['lan','jitter','heavy'],default='jitter')
parser.add_argument('--local2',action='store_true',help='Also measure a second keyboard pilot with independent prediction')
parser.add_argument('--roles',action='store_true',help='Exercise spectator role changes under delay; requires --local2')
parser.add_argument('--legacy',action='store_true',help='Record a comparison run without new-client assertions')
args=parser.parse_args();root=Path(args.assets);out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
html=root.joinpath('index.html').read_text()
html=re.sub(r'<link[^>]*>','',html)
html=re.sub(r'<script src="(?:game|netcode)\.js" defer></script>','',html)
html=html.replace('</head>','<style>'+root.joinpath('style.css').read_text()+'</style></head>')
js=root.joinpath('game.js').read_text().replace('(() => {','((location) => {',1)
pos=js.rfind('})();');js=js[:pos]+f'}})(new URL({json.dumps(args.url+"/?test=1")}));'+js[pos+5:]
# FIFO scheduling models ordered TCP/WebSocket delivery, including short bursts.
wrapper=r"""(()=>{
 window.__lag={base:60,jitter:[0,45,8,27,65,2,30,12],enabled:true};
 window.__sockets=[];const Native=window.WebSocket;
 class OrderedDelay{
  constructor(){this.items=[];this.due=0;this.timer=null;this.n=0;}
  push(run){
   const l=window.__lag,delay=l.enabled?l.base+l.jitter[this.n++%l.jitter.length]:0;
   this.due=Math.max(performance.now()+delay,this.due);
   this.items.push({due:this.due,run});
   if(this.timer===null)this.drain();
  }
  drain(){
   this.timer=null;
   while(this.items.length&&this.items[0].due<=performance.now())this.items.shift().run();
   if(this.items.length)this.timer=setTimeout(()=>this.drain(),Math.max(1,this.items[0].due-performance.now()));
  }
 }
 window.WebSocket=class extends Native{
  constructor(...args){super(...args);this._incoming=new OrderedDelay();this._outgoing=new OrderedDelay();
   window.__sockets.push(this);
   this.addEventListener('message',e=>this._incoming.push(()=>{
    if(this.readyState===Native.OPEN&&this._message)this._message.call(this,e);
   }));
  }
  set onmessage(fn){this._message=fn}get onmessage(){return this._message}
  send(data){this._outgoing.push(()=>{if(this.readyState===Native.OPEN)super.send(data)});}
 };
 window.__record=false;window.__frames=[];
 function capture(at){
  if(window.__record&&window.leqra){const s=leqra.getState();window.__frames.push({at,phase:s.phase,tanks:s.tanks,net:s.online});}
  requestAnimationFrame(capture);
 }
 requestAnimationFrame(capture);
})();"""

profiles={'lan':(0,[0]),'jitter':(60,[0,45,8,27,65,2,30,12]),'heavy':(110,[0,70,15,40,100,5,65,20])}
base,jitter=profiles[args.profile]
wrapper=wrapper.replace("base:60,jitter:[0,45,8,27,65,2,30,12]",'base:'+str(base)+',jitter:'+json.dumps(jitter))

def wrap_angle(a,b):return math.atan2(math.sin(b-a),math.cos(b-a))
def metrics(frames,tank_id):
 samples=[]
 for f in frames:
  t=next((x for x in f['tanks'] if x['id']==tank_id),None)
  if t and t['alive'] and f['phase']=='playing':samples.append((f['at'],t['angle'] if args.motion=='turn' else t['x']))
 if not samples:return {}
 start,end=samples[0][0]+1200,samples[-1][0]-300
 velocity=[]
 for a,b in zip(samples,samples[1:]):
  dt=(b[0]-a[0])/1000
  if a[0]<start or b[0]>end or dt<=0 or dt>.05:continue
  velocity.append((wrap_angle(a[1],b[1]) if args.motion=='turn' else b[1]-a[1])/dt)
 return {'frames':len(velocity),'units':('radians/second' if args.motion=='turn' else 'world units/second'),'mean_speed':statistics.mean(velocity),
  'speed_stddev':statistics.pstdev(velocity),'backward_frames':sum(v<-.05 for v in velocity),
  'near_stopped_frames':sum(abs(v)<.10 for v in velocity),
  'max_speed':max(velocity),'min_speed':min(velocity)}

with sync_playwright() as pw:
 options={'headless':True}
 if args.browser:options['executable_path']=args.browser
 browser=pw.chromium.launch(**options);errors=[];pages=[];contexts=[]
 for i in range(2):
  context=browser.new_context(viewport={'width':1365 if i==0 else 390,'height':950 if i==0 else 844},is_mobile=i==1,has_touch=i==1)
  contexts.append(context);page=context.new_page();page.set_default_timeout(10000);pages.append(page)
  page.on('pageerror',lambda e:errors.append(str(e)))
  if args.isolated:
   page.set_content(html);page.evaluate(wrapper)
   if root.joinpath('netcode.js').exists():page.add_script_tag(content=root.joinpath('netcode.js').read_text())
   page.add_script_tag(content=js)
  else:page.add_init_script(wrapper);page.goto(args.url+'/?test=1')
  page.wait_for_function('window.leqra');page.locator('[data-mode=online]' if args.legacy else '#joinOtherBtn').click()
  page.locator('#pilotName').fill('SMOOTH' if i==0 else 'OBSERVER')
 print('Clients loaded',flush=True)
 host,observer=pages
 host.locator('#createRoomBtn').click();host.wait_for_function('leqra.getState().online?.connected')
 code=host.evaluate('leqra.getState().online.code')
 observer.locator('#joinCode').fill(code);observer.locator('#joinRoomBtn').click();observer.wait_for_function('leqra.getState().online?.connected')
 print('Clients joined',flush=True)
 for page in pages:page.wait_for_function('leqra.getState().online.players.length===2')
 if args.local2:
  host.locator('#addLocalBtn').click()
  for page in pages:page.wait_for_function('leqra.getState().online.players.length===3')
 if args.roles:
  assert args.local2, '--roles requires --local2'
  # Team-specific handoff trial: choose Teams explicitly (new rooms default FFA).
  host.locator('#roomRulesBtn').click();host.locator('#rule-teamMode').select_option('teams');host.locator('#applyRulesBtn').click()
  host.wait_for_function('leqra.getState().rules.teamMode==="teams"')
  host.locator('#roomRoster [data-team="2"]').select_option('3')
  host.wait_for_function('leqra.getState().room.players.some(p=>p.id===2&&p.team===3)')
 for page in pages:
  if page.locator('#readyBtn').is_visible():page.locator('#readyBtn').click()
 host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');host.locator('#startRoomBtn').click()
 for page in pages:page.wait_for_function('leqra.getState().phase==="playing"')
 print('Match running',flush=True)
 if args.motion=='move':
  print('Installing lane fixture',flush=True)
  request=urllib.request.Request(args.url+'/_fixture/lane',data=json.dumps({'code':code}).encode(),headers={'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=5) as response:assert response.status==200
  print('Lane HTTP response received',flush=True)
  for page in pages:page.wait_for_function('leqra.getState().world.cols===20',timeout=10000)
  host.wait_for_timeout(500)
 # In-place turning has a fixed authoritative rate, independent of random walls.
 # Dispatch synthetic keyboard events without changing focus between clients.
 print('Recording motion',flush=True)
 for page in pages:page.evaluate('__frames=[];__record=true')
 key='KeyD' if args.motion=='turn' else 'KeyW'
 host.evaluate("key=>window.dispatchEvent(new KeyboardEvent('keydown',{code:key,bubbles:true}))",key)
 if args.local2:host.evaluate("key=>window.dispatchEvent(new KeyboardEvent('keydown',{code:key,bubbles:true}))",'ArrowRight' if args.motion=='turn' else 'ArrowUp')
 host.wait_for_timeout(7400)
 for page in pages:page.evaluate('__record=false')
 host.evaluate("key=>window.dispatchEvent(new KeyboardEvent('keyup',{code:key,bubbles:true}))",key)
 if args.local2:host.evaluate("key=>window.dispatchEvent(new KeyboardEvent('keyup',{code:key,bubbles:true}))",'ArrowRight' if args.motion=='turn' else 'ArrowUp')
 traces=[page.evaluate('__frames') for page in pages]
 report={'local':metrics(traces[0],0),'remote':metrics(traces[1],0),
  'profile':args.profile,'motion':args.motion,'injected_one_way_base_ms':base,'ordered_per_message_jitter_ms':jitter,
  'latency_ms':[page.evaluate('leqra.getState().online.latency') for page in pages],
  'smoothing':[page.evaluate('leqra.getState().online.smoothing||null') for page in pages],
  'browser':browser.version,'errors':errors,'isolated':args.isolated}
 if args.local2:
  report['secondary_local']=metrics(traces[0],2);report['secondary_remote']=metrics(traces[1],2)
  assert report['secondary_local']['frames']>100 and report['secondary_local']['backward_frames']==0,report
  assert report['secondary_remote']['frames']>100 and report['secondary_remote']['near_stopped_frames']<=2,report
 assert not errors,errors
 assert report['local']['frames']>100 and report['remote']['frames']>100,report
 if not args.legacy:
  assert report['local']['backward_frames']==0,report
  assert report['remote']['backward_frames']==0,report
  assert report['remote']['near_stopped_frames']<=2,report
  assert report['remote']['speed_stddev']<(.65 if args.motion=='turn' else 20),report
 # Keep both tanks driving through another member's role changes. Synthetic
 # held inputs have no OS auto-repeat to mask an accidental clearInput/history reset.
 if args.roles:
  for k in ['KeyD','ArrowRight']:host.evaluate("k=>window.dispatchEvent(new KeyboardEvent('keydown',{code:k,bubbles:true}))",k)
  host.wait_for_timeout(900);roles=[]
  for watching in [True,False,True]:
   before=host.evaluate('({primary:__test.online.seq,secondary:__test.online.secondary.seq})')
   observer.evaluate('v=>{const s=leqra.getState();__test.setPlayerSpectating([...s.room.players,...s.room.spectators].find(p=>p.id===s.online.id),v)}',watching)
   observer.wait_for_function('v=>leqra.getState().online.spectating===v',arg=watching)
   host.wait_for_timeout(450)
   seq=host.evaluate('({primary:__test.online.seq,secondary:__test.online.secondary.seq})')
   assert seq['primary']>=before['primary'] and seq['secondary']>=before['secondary'],(before,seq)
   state1=host.evaluate('__test.online.snapshots.at(-1).tanks.filter(t=>[0,2].includes(t.id)).map(t=>({id:t.id,angle:t.angle,ack:t.ack}))')
   host.wait_for_timeout(600)
   state2=host.evaluate('__test.online.snapshots.at(-1).tanks.filter(t=>[0,2].includes(t.id)).map(t=>({id:t.id,angle:t.angle,ack:t.ack}))')
   for a,b in zip(state1,state2):
    assert a['id']==b['id'] and b['ack']>a['ack'] and abs(wrap_angle(a['angle'],b['angle']))>.5, (a,b)
   roles.append({'spectating':watching,'sequences_before':before,'sequences_after':seq,'server_before':state1,'server_after':state2})
  report['spectator_role_changes_under_delay']=roles
  for k in ['KeyD','ArrowRight']:host.evaluate("k=>window.dispatchEvent(new KeyboardEvent('keyup',{code:k,bubbles:true}))",k)
 # Drop the real connection while delay injection remains active and resume.
 print('Testing resume',flush=True)
 old=host.evaluate('leqra.getState().online');n=host.evaluate('__sockets.length')
 host.evaluate('__sockets.at(-1).close(4000,"Delayed-network reconnection test")')
 host.wait_for_function('n=>__sockets.length>n&&leqra.getState().online?.connected',arg=n,timeout=12000)
 current=host.evaluate('leqra.getState().online')
 assert current['id']==old['id'] and current['code']==old['code']
 report['reconnected_under_delay']=True
 host.wait_for_timeout(700)
 for i,page in enumerate(pages):page.screenshot(path=str(out/f'jitter-{i}.png'))
 (out/'frames.json').write_text(json.dumps(traces))
 (out/'results.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report,indent=2));browser.close()

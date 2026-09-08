"""v4.2 real Go WebSocket firing, two local controllers, and viewer regression.
Injected assets/Location/storage and ordered delay; real DOM, canvas, input/socket.
The deterministic arena is provided only by the opt-in _test.go fixture.
"""
import argparse, ast, json, re, time
from pathlib import Path
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:18042');ap.add_argument('--output',default='test-output/feel42-live');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True);checks=[];errors=[];measurements=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
html=re.sub(r'<link[^>]*>|<script src="theme.js"></script>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
source=(r/'tests/network_smoothing.py').read_text();wrapper=re.search(r'wrapper=r"""(.*?)"""',source,re.S).group(1)
wrapper=wrapper.replace('base:60,jitter:[0,45,8,27,65,2,30,12]','base:90,jitter:[0,25,8,40,3,12]')
def load(b,name,w=1365,h=950,invite=''):
 c=b.new_context(viewport={'width':w,'height':h},is_mobile=w<760 or h<620,has_touch=w<760 or h<620)
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__url=String(u)}};
 for(const name of ['localStorage','sessionStorage']){const d={'leqra.name':a.name,'leqra.muted':'1'};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}}''',{'url':a.url+'/?test=1'+invite,'name':name})
 p.evaluate(wrapper);p.add_script_tag(content=(web/'theme.js').read_text());p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.__test')
 p.evaluate('''()=>{window.__fireRecord=false;window.__fireFrames=[];function record(at){if(__fireRecord){const s=__test.online.snapshots.at(-1);__fireFrames.push({at,phase:__test.phase,bullets:__test.bullets.map(b=>({id:b.id??-1,owner:b.owner,x:b.x,y:b.y,preview:!!b.preview,shot:b.shotSerial,pellet:b.pellet||0,age:b.age,bounces:b.bounces})),authority:s?.tanks.map(t=>({id:t.id,shot:t.shotSerial,cooldown:t.cooldown})),label:document.querySelector('#fireLabel').textContent,fill:document.querySelector('#cooldownFill1').style.transform,metrics:{...__test.presentationMetrics}});}requestAnimationFrame(record);}requestAnimationFrame(record);}''')
 return p,c

def fixture(code,weapon='',action='setup',player=0):
 req=Request(a.url+'/_fixture/combat42',data=json.dumps({'code':code,'weapon':weapon,'action':action,'player':player}).encode(),headers={'Content-Type':'application/json'})
 with urlopen(req,timeout=5) as res:return json.load(res)

with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');contexts=[]
 try:
  host,hc=load(b,'HOST');contexts.append(hc);host.locator('#addLocalBtn').click();host.locator('#copyInviteBtn').click();host.wait_for_function('leqra.getState().online?.connected')
  host.wait_for_function('__test.online.roomData?.players.some(p=>p.kind==="local")');code=host.evaluate('__test.online.code');ids=host.evaluate('[__test.online.id,__test.online.roomData.players.find(p=>p.kind==="local").id]')
  viewer,vc=load(b,'VIEWER',390,844,invite='&room='+code+'&spectate=1');contexts.append(vc);viewer.locator('#joinRoomBtn').click();viewer.wait_for_function('leqra.getState().online?.spectating')
  host.locator('#startRoomBtn').click();host.wait_for_function("leqra.getState().phase==='playing'")
  check(len(ids)==2 and ids[0]!=ids[1],'Two independently controlled local tanks plus a real online viewer')
  for power,hold in [('',.09),('rapid',.43),('scatter',.09),('homing',.09),('grenade',.09),('cannon',.09),('laser',.09)]:
   gen=fixture(code,power)['generation'];host.wait_for_function('(g)=>__test.online.generation===g',arg=gen);viewer.wait_for_function('(g)=>__test.online.generation===g',arg=gen);host.wait_for_timeout(160)
   host.evaluate('window.__fireFrames=[];window.__fireRecord=true;window.__pressedAt=performance.now()')
   host.keyboard.down('f');host.keyboard.down('Space');host.wait_for_timeout(int(hold*1000));host.keyboard.up('f');host.keyboard.up('Space')
   host.wait_for_timeout(1100);host.evaluate('window.__fireRecord=false');frames=host.evaluate('__fireFrames');pressed=host.evaluate('__pressedAt');measurements.append({'power':power or 'standard','pressedAt':pressed,'frames':frames})
   m=host.evaluate('__test.presentationMetrics');check(m['previews']>=2 and m['confirmed']>=0,f'{power or "standard"}: both local firing responses predicted')
   check(m['suppressedSounds']>=2,f'{power or "standard"}: accepted shots do not replay local firing sounds')
   auth=host.evaluate('(ids)=>__test.online.snapshots.at(-1).tanks.filter(t=>ids.includes(t.id)).map(t=>t.shotSerial)',ids)
   check(len(auth)==2 and all(n>=1 for n in auth),f'{power or "standard"}: Go confirms both independent shots')
   if power not in ['laser','rapid']:
    first=next((f for f in frames if any(x['owner']==ids[0] and x['preview'] for x in f['bullets'])),None)
    check(first is not None and all(t['shot']==0 for t in first['authority'] if t['id']==ids[0]),f'{power or "standard"}: visual projectile exists before server acknowledgement')
    delay=first['at']-pressed;check(delay<100,f'{power or "standard"}: first-frame response ({delay:.1f} ms under injected delay)')
   if power in ['','cannon']:
    # Compare the same owner/volley through preview -> confirmed handoff, before rim bounce.
    points=[]
    for f in frames:
     x=next((x for x in f['bullets'] if x['owner']==ids[0] and x.get('shot')==1 and x['pellet']==0 and x['bounces']==0),None)
     if x:points.append(x['x'])
    backwards=sum(y<x-.5 for x,y in zip(points,points[1:]));check(backwards==0,f'{power or "standard"}: no projectile rewind on server confirmation')
   if power=='grenade':
    before=host.evaluate('__test.online.snapshots.at(-1).events.filter(e=>e.type==="blast").length');host.keyboard.press('f');host.wait_for_timeout(500)
    check(host.evaluate('(id)=>!__test.online.snapshots.at(-1).bullets.some(b=>b.owner===id&&b.kind==="grenade")',ids[0]),'Fresh Fire press remotely detonates P1 grenade after prediction')
    check(host.evaluate('(id)=>__test.online.snapshots.at(-1).bullets.some(b=>b.owner===id&&b.kind==="grenade")',ids[1]),'P1 detonation does not detonate local P2 grenade')
  # Actual round win while the last weapon is still cooling down.
  fixture(code,action='win',player=ids[0]);host.wait_for_function('__test.phase==="roundOver"');host.evaluate('__fireFrames=[];__fireRecord=true');host.wait_for_timeout(1500);host.evaluate('__fireRecord=false')
  f=host.evaluate('__fireFrames');labels={v['label'] for v in f};fills={v['fill'] for v in f};check(labels=={'DONE'} and len(fills)==1,'Winning cooldown and Fire label remain completely stable across real snapshots')
  host.wait_for_function('__test.phase==="matchOver"');viewer.wait_for_function('__test.phase==="matchOver"');host.wait_for_timeout(200)
  check(host.locator('#cooldownText1').inner_text()=='MATCH COMPLETE','Completed-match HUD does not advertise a live cooldown')
  host.screenshot(path=str(out/'winner-desktop.png'));viewer.screenshot(path=str(out/'winner-viewer-390.png'))
  # Connected identity and metrics survive graceful resume, without stale previews.
  old=host.evaluate('__test.online.id');host.evaluate('__test.online.socket.close(4000,"test resume")');host.wait_for_function('!__test.online.connected');host.wait_for_function('__test.online.connected',timeout=15000)
  check(host.evaluate('__test.online.id')==old,'Reconnect retains primary identity')
  check(host.evaluate('__test.online.shots.previews.size')==0,'Reconnect has no stale speculative projectiles')
  check(not errors,'No JavaScript errors: '+str(errors))
 finally:
  for c in contexts:c.close()
  b.close();(out/'results.json').write_text(json.dumps({'version':'4.2.0','passed':len(checks),'checks':checks,'errors':errors},indent=2));(out/'frames.json').write_text(json.dumps(measurements))
print('TOTAL',len(checks))

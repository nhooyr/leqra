"""v4.0 queue UI + real Go sockets. Browser assets are injected because the
sandbox blocks navigation; only Location/History/storage have test adapters.
Use TestBrowserFixture for opaque about:blank origins, never a production bypass.
"""
import argparse,json,re,threading,time
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright
from websockets.sync.client import connect
ap=argparse.ArgumentParser();ap.add_argument('url',nargs='?',default='http://127.0.0.1:18041');ap.add_argument('--output',default='test-output/matchmaking40');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[];peers=[]
def check(ok,text):
 assert ok,text
 checks.append(text);print('PASS',text,flush=True)
class Peer:
 def __init__(self):
  self.ws=connect(args.url.replace('http','ws',1)+'/ws',origin=args.url,compression=None,proxy=None);self.messages=[];self.cv=threading.Condition();self.thread=threading.Thread(target=self.read,daemon=True);self.thread.start();peers.append(self)
 def read(self):
  try:
   for data in self.ws:
    with self.cv:self.messages.append(json.loads(data));self.cv.notify_all()
  except Exception:pass
 def send(self,**m):self.ws.send(json.dumps(m))
 def wait(self,pred,after=0,timeout=10):
  end=time.time()+timeout
  with self.cv:
   while True:
    for m in self.messages[after:]:
     if pred(m):return m
    left=end-time.time()
    if left<=0:raise AssertionError('wire timeout '+str(self.messages[-3:]))
    self.cv.wait(min(left,.2))
 def op(self,kind,pred=None,**m):
  n=len(self.messages);self.send(type=kind,**m);return self.wait(pred or (lambda m:m['type']=='room'),after=n)
 def leave(self):
  try:self.send(type='leave');time.sleep(.04);self.ws.close()
  except Exception:pass
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
def load(b,name,w=1365,h=950,invite=''):
 mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1)
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept());p.set_content(html)
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(state,title,url){this.state=state;window.__updatedURL=String(url);}};
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,'localStorage',{value:store({'leqra.muted':'1','leqra.name':a.name})});Object.defineProperty(window,'sessionStorage',{value:store({})});}''',{'url':args.url+'/?test=1'+invite,'name':name})
 p.add_script_tag(content=(web/'theme.js').read_text());p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p,c

def queue_party_wire(n,key):
 people=[Peer() for _ in range(n)];w=people[0].op('create',lambda m:m['type']=='welcome',name='Opponent 1');code=w['room']
 for i,p in enumerate(people[1:]):p.op('join',lambda m:m['type']=='welcome',code=code,name='Opponent '+str(i+2))
 r=people[0].op('queue_join',lambda m:m['type']=='room' and m.get('queue'),queue=key);qid=r['queue']['id']
 for p in people[1:]:p.op('queue_accept',lambda m:m['type']=='room' and m.get('queue'),queueId=qid,ready=True)
 return people
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  # Responsive six-card chooser; actual native pointer clicks on every layout.
  for w,h in [(1365,950),(390,844),(320,568),(844,390)]:
   p,c=load(b,'Menu Test',w,h);p.locator('#matchmakingBtn').click()
   check(p.locator('#queueDialog').evaluate('(e)=>e.open') and p.locator('[data-queue]').count()==6,f'{w}x{h}: six real queue cards open')
   for key in ['elimination-1','elimination-2','elimination-3','ctf-3','koth-3','ffa-8']:
    p.locator('[data-queue="'+key+'"]').click();check(p.locator('[data-queue="'+key+'"]').get_attribute('aria-pressed')=='true',f'{w}x{h}: select {key}')
   check(p.evaluate('document.body.scrollWidth<=innerWidth+1'),f'{w}x{h}: no horizontal overflow')
   p.locator('[data-queue="ctf-3"]').click();p.screenshot(path=str(out/f'queues-{w}x{h}.png'));p.locator('#queueCloseBtn').click();c.close()
  # Default bot roster queues only its real owner, and cancellation is reversible.
  solo,sc=load(b,'SOLO TEST');solo.locator('#matchmakingBtn').click();solo.locator('#queueStartBtn').click();solo.wait_for_function('leqra.getState().room?.queue?.stage==="searching"')
  state=solo.evaluate('leqra.getState()');home=state['online']['code'];check(state['room']['queue']['players']==1 and len(state['room']['players'])==4,'One real pilot queues; three default bots remain private')
  check(parse_qs(urlparse(solo.evaluate('window.__updatedURL')).query)['room']==[home],'Publishing for queue updates the invite URL adapter')
  solo.locator('#queueCloseBtn').click();check(solo.evaluate('!!leqra.getState().room.queue'),'Closing chooser does not cancel queue')
  solo.locator('#matchmakingBtn').click();solo.locator('#queueCancelBtn').click();solo.wait_for_function('!leqra.getState().room.queue');check(solo.evaluate('leqra.getState().online.code')==home,'Cancel retains same online party and lobby')
  solo.locator('#queueCloseBtn').click();solo.evaluate('__test.online.socket.send(JSON.stringify({type:"leave"}))');sc.close()
  # Three-real-player party: host + local keyboard P2 + remote friend.
  host,hc=load(b,'Party Host');host.locator('#addLocalBtn').click();host.locator('#roomP2Callsign').fill('Keyboard Ally');host.locator('#roomP2CallsignForm button').click();host.locator('#copyInviteBtn').click();host.wait_for_function('leqra.getState().online?.connected');home=host.evaluate('leqra.getState().online.code')
  friend,fc=load(b,'Remote Ally',320,568,'&room='+home);friend.wait_for_function('leqra.getState().online?.connected');host.wait_for_function('leqra.getState().room.players.length===6')
  observer=Peer();observer.op('join',lambda m:m['type']=='welcome',code=home,name='Home Viewer',spectating=True)
  host.locator('#matchmakingBtn').click();host.locator('[data-queue="elimination-1"]').click();check(host.locator('#queueStartBtn').is_disabled(),'Three-person party cannot enter 1v1')
  host.locator('[data-queue="ffa-8"]').click();check(host.locator('#queueStartBtn').is_disabled() and 'solo-entry' in host.locator('#queueNotice').inner_text(),'Free-for-all rejects allied party entry')
  host.locator('[data-queue="ctf-3"]').click();host.locator('#queueStartBtn').click();host.wait_for_function('leqra.getState().room?.queue?.stage==="confirming"');friend.wait_for_function('document.querySelector("#queueDialog").open')
  check(friend.locator('#queueAcceptBtn').is_visible(),'Remote friend must explicitly confirm selected queue')
  q=host.evaluate('leqra.getState().room.queue');check(q['players']==3 and sum(p['accepted'] for p in q['members'])==2,'Local P2 counts as a real player; host confirms both keyboard pilots')
  check(friend.locator('#queueStartBtn').is_hidden(),'Guest cannot choose or start a different queue')
  friend.screenshot(path=str(out/'party-confirm-320.png'));friend.locator('#queueAcceptBtn').click();host.wait_for_function('leqra.getState().room.queue?.stage==="searching"');friend.wait_for_function('leqra.getState().room.queue?.stage==="searching"')
  check(True,'Search activates only after friend consent');host.screenshot(path=str(out/'party-searching.png'))
  # Search chat stays in private room and causes no movement inputs.
  friend.locator('#queueCloseBtn').click();friend.locator('#chatBtn').click();friend.locator('#chatInput').fill('Ready together');friend.locator('#chatSendBtn').click();friend.locator('#chatCloseBtn').click()
  observer.wait(lambda m:m['type']=='chat' and m['message']['text']=='Ready together');check(True,'Room chat still reaches a private spectator during the search')
  opp=queue_party_wire(3,'ctf-3');host.wait_for_function('!!leqra.getState().room?.matchmaking',timeout=15000);friend.wait_for_function('!!leqra.getState().room?.matchmaking')
  hs=host.evaluate('leqra.getState()');fs=friend.evaluate('leqra.getState()');battle=hs['online']['code'];check(battle!=home and battle==fs['online']['code'],'Party moves together to a distinct server-created battle')
  roster=hs['room']['players'];own=[p for p in roster if p['name'] in ['Party Host','Keyboard Ally','Remote Ally']];check(len(own)==3 and len({p['team'] for p in own})==1,'All three party members share one team')
  check(len(roster)==6 and all(p['kind']!='bot' for p in roster),'Full 3v3 lineup contains six real tanks, no bots')
  check(hs['rules']['mode']=='ctf' and hs['rules']['mapSize']=='huge' and hs['room']['host']==-1,'CTF queue applies fixed 14x12 rules and no player-host')
  check(not host.locator('#queueDialog').evaluate('(e)=>e.open') and not friend.locator('#queueDialog').evaluate('(e)=>e.open'),'Match transfer closes queue dialogs automatically')
  observer.wait(lambda m:m['type']=='room' and m.get('awayMatch')==battle);check(True,'Unqueued spectator remains in original room with a watchable match reference')
  check(parse_qs(urlparse(host.evaluate('window.__updatedURL')).query)['room']==[battle],'Match transfer updates public invite URL adapter')
  host.wait_for_function('leqra.getState().phase==="playing"',timeout=15000);friend.wait_for_function('leqra.getState().phase==="playing"',timeout=15000)
  check(host.evaluate('leqra.getState().world.cols')==14,'Countdown automatically leads into the actual maze')
  host.bring_to_front();host.keyboard.down('f');host.keyboard.down('Space');host.wait_for_timeout(80);host.keyboard.up('f');host.keyboard.up('Space')
  host.wait_for_function('''()=>{const s=leqra.getState(),me=s.online.id,p2=s.room.players.find(p=>p.kind==='local'&&p.owner===me),ts=__test.online.snapshots.at(-1).tanks;return p2&&[me,p2.id].every(id=>ts.find(t=>t.id===id)?.ack>0);}''')
  check(True,'Primary F and secondary Space retain independent online input acknowledgements')
  check(host.locator('#weaponLabel2').is_visible(),'Player 2 ammo remains visible in matched gameplay')
  host.locator('#roomBtn').click();host.wait_for_function('!document.querySelector("#onlineMenuScreen").hidden')
  check('BACK TO MY PARTY' not in host.locator('#onlineMenuScreen').inner_text() and host.locator('#partyReturnMenuBtn').count()==0,'Online match menu has no BACK TO MY PARTY action')
  host.locator('#onlineReturnBtn').click();host.wait_for_function('document.querySelector("#onlineMenuScreen").hidden')
  friend.screenshot(path=str(out/'matched-ctf-320.png'))
  # Match spectator links remain names-first and cannot take an empty tank seat.
  watch,wc=load(b,'Match Viewer',390,844,'&room='+battle+'&spectate=1');watch.wait_for_function('document.querySelector("#joinDialog").open');watch.locator('#pilotName').fill('Match Viewer');watch.locator('#joinRoomBtn').click();watch.wait_for_function('leqra.getState().online?.spectating');check(watch.evaluate('leqra.getState().online.code')==battle,'Watch link joins matched arena as spectator after callsign confirmation')
  check(watch.locator('#spectatorPlayBtn').is_disabled() and watch.locator('#spectatorPlayBtn').inner_text()=='SPECTATING ONLY','Matched spectator HUD clearly disables new tank entry while remaining Spectating')
  check(watch.locator('#toggleSpectateBtn').is_disabled(),'Matched spectator room role control is disabled, not a failing action')
  # Live reconnect preserves queue membership, both pilots and return reservation.
  old=host.evaluate('leqra.getState().online.id');host.evaluate('__test.online.socket.close(4000,"queue reconnect test")');host.wait_for_function('!leqra.getState().online.connected');host.wait_for_function('leqra.getState().online.connected',timeout=15000)
  check(host.evaluate('leqra.getState().online.id')==old and host.evaluate('leqra.getState().room.players.some(p=>p.kind==="local"&&p.name==="Keyboard Ally")'),'Reconnect preserves both matched pilots and identities')
  # Abandon opposing side: the result screen and private-party return still work.
  for p in opp:p.leave()
  host.wait_for_function('leqra.getState().phase==="matchOver"',timeout=10000);host.wait_for_function('document.querySelector("#victoryDialog").open');friend.wait_for_function('document.querySelector("#victoryDialog").open');watch.wait_for_function('document.querySelector("#victoryDialog").open')
  check('WINS' in host.locator('#victoryTitle').inner_text() and host.locator('#victoryStats').is_visible(),'Public forfeit resolves to a results screen with match statistics')
  check(host.locator('#victoryEyebrow').inner_text()=='VICTORY!' and 'CONGRAT' not in host.locator('#victoryDialog').inner_text().upper(),'Winning result celebrates only the winning local side')
  check(host.locator('#victoryAgainBtn').is_visible() and host.locator('#victoryAgainBtn').inner_text().startswith('REMATCH') and 'queue-rematch' in (host.locator('#victoryAgainBtn').get_attribute('class') or '') and host.locator('#victoryAgainBtn').evaluate("e=>getComputedStyle(e).backgroundColor")=='rgb(57, 255, 136)','Queued participant gets the neon green REMATCH action')
  check(host.locator('#victoryPartyBtn').count()==0 and watch.locator('#victoryAgainBtn').is_hidden(),'Legacy result party button is removed and spectators cannot rematch')
  host.screenshot(path=str(out/'matched-results.png'));host.locator('#victoryCloseBtn').click();host.wait_for_function('(code)=>leqra.getState().online.code===code',arg=home)
  check(host.evaluate('leqra.getState().room.awayMatch')==battle,'Returning early reserves the lobby until remaining friend returns')
  check(host.locator('#toggleSpectateBtn').is_disabled(),'Reserved source lobby disables role changes until friends return')
  friend.locator('#victoryCloseBtn').click();friend.wait_for_function('(code)=>leqra.getState().online.code===code',arg=home);host.wait_for_function('!leqra.getState().room.awayMatch')
  r=host.evaluate('leqra.getState().room');check(len(r['players'])==6 and sum(p['kind']=='bot' for p in r['players'])==3,'Return restores private bot roster and three real players')
  check(r['rules']['teamMode']=='ffa' and r['rules']['mapSize']=='large','Private Free-for-all rules and default map were not overwritten')
  check(any(p['name']=='Keyboard Ally' and p['kind']=='local' for p in r['players']),'Player 2 custom callsign survives battle and return')
  check(observer.wait(lambda m:m['type']=='room' and not m.get('awayMatch')) is not None,'Original spectator stays in the private room')
  host.locator('#matchmakingBtn').click();host.locator('[data-queue="ctf-3"]').click();host.locator('#queueStartBtn').click();host.wait_for_function('leqra.getState().room.queue?.stage==="confirming"');friend.wait_for_function('document.querySelector("#queueAcceptBtn").offsetParent!==null');check(True,'Another match requires fresh remote consent, not stale previous readiness')
  friend.locator('#queueCancelBtn').click();host.wait_for_function('!leqra.getState().room.queue');check(True,'A participating friend can cancel the next party search')
  check(not errors,'No uncaught browser errors')
  for c in [hc,fc,wc]:c.close()
  report={'version':re.search(r"GAME_VERSION='([^']+)'",js).group(1),'passed':len(checks),'checks':checks,'errors':errors,'limitations':'Chromium desktop/mobile emulation; exact assets; synthetic Location/History/storage; real local Go sockets. No physical phones or public deployment.'};(out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:
  for p in peers:p.leave()
  b.close()

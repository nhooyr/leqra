"""v4.0 production matchmaking integration (no fixtures, grants, or mocks).
Run: python tests/matchmaking_protocol.py http://localhost:8080 --output results.json
Requires the optional Python websockets test dependency, not a game dependency.
"""
import argparse,asyncio,json,time,urllib.request,urllib.error
from pathlib import Path
from collections import Counter
from urllib.parse import urlsplit
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed
ap=argparse.ArgumentParser();ap.add_argument('url');ap.add_argument('--expect-version',default='4.0.0');ap.add_argument('--output',default='matchmaking-protocol.json');args=ap.parse_args()
BASE=args.url.rstrip('/');u=urlsplit(BASE);ORIGIN=f'{u.scheme}://{u.netloc}';WS=f'{"wss" if u.scheme=="https" else "ws"}://{u.netloc}/ws'
checks=[];all_peers=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
class Peer:
 def __init__(self,ws):
  self.ws=ws;self.messages=[];self.last_action=0;self.task=asyncio.create_task(self.read());all_peers.append(self)
 async def read(self):
  try:
   async for raw in self.ws:self.messages.append(json.loads(raw))
  except ConnectionClosed:pass
 async def send(self,kind,**data):
  if kind not in ('input','ping'):
   await asyncio.sleep(max(0,.16-(time.monotonic()-self.last_action)));self.last_action=time.monotonic()
  await self.ws.send(json.dumps({'type':kind,**data}))
 async def wait(self,pred,after=0,timeout=12):
  until=time.monotonic()+timeout
  while time.monotonic()<until:
   for m in self.messages[after:]:
    if pred(m):return m
   await asyncio.sleep(.01)
  raise AssertionError('No expected packet; tail='+str(self.messages[-2:]))
 async def op(self,kind,pred,**data):
  start=len(self.messages);await self.send(kind,**data);return await self.wait(pred,start)
 async def close(self):
  try:await self.send('leave')
  except ConnectionClosed:pass
  await self.ws.close();await self.task
async def peer():return Peer(await connect(WS,origin=ORIGIN,compression=None,proxy=None,max_size=2_000_000))
async def party(n,name):
 ps=[await peer() for _ in range(n)];w=await ps[0].op('create',lambda m:m['type']=='welcome',name=name+'0');code=w['room'];ws=[w]
 for i,p in enumerate(ps[1:]):ws.append(await p.op('join',lambda m:m['type']=='welcome',code=code,name=name+str(i+1)))
 return ps,code,ws
async def queue(ps,key):
 r=await ps[0].op('queue_join',lambda m:m['type']=='room' and m.get('queue'),queue=key);qid=r['queue']['id']
 for p in ps[1:]:await p.op('queue_accept',lambda m:m['type']=='room' and m.get('queue'),queueId=qid,ready=True)
 return qid
async def main():
 config=json.load(urllib.request.urlopen(BASE+'/api/config'));health=json.load(urllib.request.urlopen(BASE+'/healthz'))
 check(health['version']==args.expect_version and config.get('matchmaking') and len(config['queues'])==6,'Production health/config expose six supported queues')
 try:urllib.request.urlopen(BASE+'/__test/grant');absent=False
 except urllib.error.HTTPError as e:absent=e.code==404
 check(absent,'Test-only grant endpoint is absent from production')
 # All six queues, real sockets and automatic real countdowns.
 for d in config['queues']:
  groups=[];homes=[];welcomes=[]
  sizes=[1]*8 if d['teamSize']==0 else [d['teamSize'],d['teamSize']]
  for i,n in enumerate(sizes):
   ps,code,ws=await party(n,f'Q{i}-');groups.append(ps);homes.append(code);welcomes+=ws;await queue(ps,d['key'])
  everyone=[p for g in groups for p in g]
  transfers=await asyncio.gather(*(p.wait(lambda m:m['type']=='welcome' and m.get('transfer')=='match_found') for p in everyone))
  codes={w['room'] for w in transfers};check(len(codes)==1 and not codes.intersection(homes),d['key']+': full queue assembles one fresh battle')
  code=transfers[0]['room'];room=await everyone[0].wait(lambda m:m['type']=='room' and m['code']==code);teams=Counter(p['team'] for p in room['players'])
  check(len(room['players'])==d['players'] and all(p['kind']!='bot' for p in room['players']),d['key']+': exact human-only population')
  check((teams==Counter({0:8})) if d['teamSize']==0 else teams==Counter({1:d['teamSize'],2:d['teamSize']}),d['key']+': balanced teams or eight independent FFA sides')
  check(room['host']==-1 and room['matchmaking']['locked'] and not room['canStart'],d['key']+': no player can control the public match')
  rules=room['rules'];check(rules['mode']==d['mode'] and rules['mapSize']==d['map'],d['key']+': fixed mode and map applied')
  s=await everyone[0].wait(lambda m:m['type']=='state' and m.get('world') and m['world']['cols']==d['cols'] and len(m['tanks'])==d['players'])
  check(s['world']['rows']==d['rows'],d['key']+': full authoritative map received')
  for ps in groups:
   assigned=[]
   for p in ps:
    w=next(x for x in p.messages if x.get('transfer')=='match_found');assigned.append(next(x['team'] for x in room['players'] if x['id']==w['id']))
   check(len(set(assigned))==1,d['key']+': each original party stays on one side')
  await everyone[0].wait(lambda m:m['type']=='state' and m['phase']=='playing',timeout=10)
  check(True,d['key']+': starts automatically after countdown, no host click')
  # Teams are fixed even for the former source-room host. No hidden creation shortcuts.
  err=await everyone[0].op('start',lambda m:m['type']=='error',scores=[99]*8)
  check(err['code']=='match_locked',d['key']+': forged host start rejected')
  tokens=[w['token'] for w in welcomes]
  check(all(not any(token in json.dumps(m) for token in tokens) for p in everyone for m in p.messages if m['type']!='welcome'),d['key']+': no credentials in shared state')
  for idx,ps in enumerate(groups):
   for p in ps:
    w=await p.op('return_party',lambda m:m['type']=='welcome' and m.get('transfer')=='party_return');check(w['room']==homes[idx],d['key']+': member returns to their own original lobby')
  for p in everyone:await p.close()
 # Exact packing of a duo and a solo against a trio, plus confirmation/cancellation.
 a,home,aw=await party(2,'PartyA');solo,_,_=await party(1,'Solo');trio,_,_=await party(3,'PartyB')
 err=await a[1].op('queue_join',lambda m:m['type']=='error',queue='ctf-3');check(err['code']=='not_host','Guest cannot initiate party search')
 for key in ['elimination-1','ffa-8','not-a-queue']:
  err=await a[0].op('queue_join',lambda m:m['type']=='error',queue=key);check(err['code'] in ['party_too_large','ffa_solo','bad_queue'],'Invalid/undersized queue rejected: '+key)
 r=await a[0].op('queue_join',lambda m:m['type']=='room' and m.get('queue'),queue='ctf-3');qid=r['queue']['id'];check(r['queue']['stage']=='confirming','Remote friends must consent before the ticket searches')
 await solo[0].send('queue_info');cat=await solo[0].wait(lambda m:m['type']=='queue_catalog');check(next(x for x in cat['queues'] if x['definition']['key']=='ctf-3')['waitingPlayers']==0,'Unconfirmed party is not counted as searching')
 late=await peer();w=await late.op('join',lambda m:m['type']=='welcome',code=home,name='Observer');check(w['spectating'] and w['busy'],'New visitor cannot mutate a queued party: enters spectator')
 err=await late.op('queue_cancel',lambda m:m['type']=='error',queueId=qid);check(err['code']=='not_participant','Spectator cannot cancel another party search')
 await a[1].op('queue_cancel',lambda m:m['type']=='queue_cancelled',queueId=qid);check(True,'Queued friend can cancel the whole party search')
 r=await a[0].op('queue_join',lambda m:m['type']=='room' and m.get('queue'),queue='ctf-3');qid2=r['queue']['id']
 err=await a[1].op('queue_accept',lambda m:m['type']=='error',queueId=qid,ready=True);check(err['code']=='stale_queue','Old confirmation cannot accept a new invitation')
 await a[1].op('queue_accept',lambda m:m['type']=='room' and m.get('queue') and m['queue']['stage']=='searching',queueId=qid2,ready=True)
 await queue(solo,'ctf-3');await queue(trio,'ctf-3');w=await a[0].wait(lambda m:m.get('transfer')=='match_found');code=w['room'];r=await a[0].wait(lambda m:m['type']=='room' and m['code']==code)
 at={p['team'] for p in r['players'] if p['name'].startswith('PartyA')};st={p['team'] for p in r['players'] if p['name'].startswith('Solo')};bt={p['team'] for p in r['players'] if p['name'].startswith('PartyB')}
 check(len(at)==1 and at==st and at!=bt,'Mixed-sized tickets pack 2+1 versus 3 without splitting friends')
 await late.wait(lambda m:m['type']=='room' and m.get('awayMatch')==code);check(True,'Private spectator remains home and sees match watch reference')
 viewer=await peer();vw=await viewer.op('join',lambda m:m['type']=='welcome',code=code,name='Match Viewer');check(vw['spectating'],'Fresh match link visitor cannot replace a contestant')
 err=await viewer.op('spectate',lambda m:m['type']=='error',spectating=False);check(err['code']=='match_locked','Matched spectator cannot claim a seat')
 err=await viewer.op('return_party',lambda m:m['type']=='error');check(err['code']=='no_party','Unrelated viewer cannot return into a private origin')
 party_start=len(a[1].messages);viewer_start=len(viewer.messages);await a[0].send('chat',text='Matched together');await a[1].wait(lambda m:m['type']=='chat' and m.get('channel','room')=='room' and m['message']['text']=='Matched together',after=party_start);check(True,'Matched normal chat stays with the travelling party')
 await asyncio.sleep(.1);check(not any(m['type']=='chat' and m['message']['text']=='Matched together' for m in viewer.messages[viewer_start:]),'Unrelated match spectators do not receive private party chat')
 check(not any(m['type']=='chat' and m['message']['text']=='Matched together' for m in late.messages),'Matched party chat does not leak into the source lobby')
 # Resume using the pre-transfer home URL/token (a refresh racing the welcome).
 oldid=w['id'];await a[0].ws.close();await a[0].task
 fresh=await peer();rw=await fresh.op('join',lambda m:m['type']=='welcome',code=home,token=aw[0]['token'],name='Ignored')
 check(rw['resumed'] and rw['room']==code and rw['id']==oldid,'Origin credential safely follows an in-progress match transfer')
 a[0]=fresh
 # Completing by real departures retains normal results for every remaining client.
 for p in trio:await p.close()
 end=await a[0].wait(lambda m:m['type']=='state' and m['phase']=='matchOver');check(end.get('matchStats') is not None,'Forfeit retains authoritative finished statistics')
 # Use actual report field discovered from schema (test should fail rather than invent).
 rw=await a[0].op('return_party',lambda m:m.get('transfer')=='party_return');check(rw['room']==home,'Surviving party returns without a new WebSocket')
 await a[1].op('return_party',lambda m:m.get('transfer')=='party_return');r=await a[0].wait(lambda m:m['type']=='room' and m['code']==home and not m.get('awayMatch'));check(len(r['players'])==2,'Original friend roster restored with no duplicates')
 for p in a+solo+[late,viewer]:await p.close()
 report={'version':args.expect_version,'passed':len(checks),'checks':checks,'limits':'Real loopback production HTTP/WebSocket handlers. No fixture grants, public hosting, region/skill matching, or deployment load test.'}
 Path(args.output).parent.mkdir(parents=True,exist_ok=True);Path(args.output).write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
async def run():
 try:await main()
 finally:
  for p in all_peers:
   try:await p.close()
   except Exception:pass
asyncio.run(run())

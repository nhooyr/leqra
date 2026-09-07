"""Production handler checks for sharing, virtual seats, teams and ownership."""
import asyncio,json,secrets
from pathlib import Path
import protocol_smoke as wire
async def main():
 peers=[];checks=[]
 def check(v,s):
  assert v,s
  checks.append(s);print('PASS',s,flush=True)
 async def new():
  p=await wire.peer();peers.append(p);return p
 try:
  h=await new();code='Mixed team '+secrets.token_hex(5)
  await h.send(type='publish',code=code,roster=[dict(name='HOST',kind='human',team=1),dict(name='P2',kind='local',team=1),dict(name='BOT',kind='bot',difficulty='hard',team=2)])
  welcome=await h.wait(lambda m:m['type']=='welcome');r=await h.wait(lambda m:m['type']=='room' and len(m['players'])==3)
  check(welcome['created'] and r['host']==0 and r['canStart'],'One controller can host a mixed match')
  check(r['players'][1]['kind']=='local' and r['players'][1]['owner']==0,'Local seat has explicit controller owner')
  check(r['players'][2]['kind']=='bot' and r['players'][2]['difficulty']=='hard','Server imports chosen bot difficulty')
  check(all('token' not in p for p in r['players']),'Roster contains no reconnect credentials')
  c=await new();await c.send(type='publish',code=code,roster=[dict(name='OTHER',kind='human',team=1)])
  e=await c.wait(lambda m:m['type']=='error');check(e['code']=='room_exists','Share cannot overwrite an existing room')
  g=await new();await g.send(type='join',code=code,name='GUEST');await g.wait(lambda m:m['type']=='welcome')
  for op in [dict(type='add',kind='bot',difficulty='easy'),dict(type='configure',target=0,member=r['players'][0]['member'],team=4),dict(type='lobby')]:
   n=len(g.messages);await g.send(**op);e=await g.wait(lambda m:m['type']=='error',after=n);check(e['code']=='not_host','Guest cannot '+op['type'])
  n=len(h.messages);await h.send(type='configure',target=2,member=r['players'][2]['member'],difficulty='easy',team=2)
  await h.wait(lambda m:m['type']=='room' and m['players'][2]['difficulty']=='easy',after=n)
  await g.send(type='ready',ready=True);await h.wait(lambda m:m['type']=='room' and m['canStart'] and len(m['players'])==4)
  await h.send(type='start');s=await h.wait(lambda m:m['type']=='state' and m['phase']=='playing')
  check(s['tanks'][1]['alive'] and s['tanks'][2]['bot'],'Local and bot seats enter the real simulation')
  check(s['tanks'][2]['difficulty']=='easy' and s['tanks'][0]['team']==s['tanks'][1]['team']==1,'Host edits take effect in authoritative tanks')
  n=len(h.messages);await h.send(type='input',seq=20,left=True);await h.send(type='input',player=1,seq=2,right=True)
  s=await h.wait(lambda m:m['type']=='state' and any(t['id']==1 and t['ack']==2 for t in m['tanks']),after=n)
  check(s['tanks'][0]['ack']==20 and s['tanks'][1]['ack']==2,'Separate primary and secondary acknowledgements')
  for id in [0,1,2]:
   n=len(g.messages);await g.send(type='input',player=id,seq=999,fire=True);e=await g.wait(lambda m:m['type']=='error',after=n);check(e['code']=='not_owned','Guest cannot forge input for seat '+str(id))
  n=len(h.messages);await h.send(type='configure',target=2,member=r['players'][2]['member'],team=1);e=await h.wait(lambda m:m['type']=='error',after=n);check(e['code']=='match_active','Teams cannot change mid-round')
  await asyncio.sleep(1.1) # respect production action budget
  n=len(h.messages);await h.send(type='lobby');r2=await h.wait(lambda m:m['type']=='room' and m['phase']=='lobby',after=n)
  check(len(r2['players'])==4 and all(p['score']==0 for p in r2['players']),'Return to room resets match but retains all seats')
  await h.send(type='leave');r3=await g.wait(lambda m:m['type']=='room' and len(m['players'])==2)
  check(r3['host']==3 and not any(p['kind']=='local' for p in r3['players']),'Owner leave cleans secondary and elects human guest')
  report={'version':'3.1.0','checks_passed':len(checks),'checks':checks,'handler':'normal production HTTP/WebSocket handler; loopback TCP'}
  (Path(__file__).parent/'results/unified-protocol-v3.1.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
 finally:
  await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

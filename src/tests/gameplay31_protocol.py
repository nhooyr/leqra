"""v3.1 naming checks through the production WebSocket handler (no test endpoints)."""
import asyncio,json,secrets
from pathlib import Path
import protocol_smoke as wire
async def main():
 peers=[];checks=[]
 def check(v,s):
  assert v,s
  checks.append(s);print('PASS',s,flush=True)
 async def peer():
  p=await wire.peer();peers.append(p);return p
 try:
  h=await peer();code='HUD31 '+secrets.token_hex(5)
  await h.send(type='publish',code=code,roster=[dict(name='HOST',kind='human',team=1),dict(name='PLAYER 2',kind='local',team=1)])
  welcome=await h.wait(lambda m:m['type']=='welcome');r=await h.wait(lambda m:m['type']=='room' and len(m['players'])==2);local=r['players'][1]
  g=await peer();await g.send(type='join',code=code,name='GUEST');await g.wait(lambda m:m['type']=='welcome');await g.send(type='ready',ready=True)
  await h.wait(lambda m:m['type']=='room' and len(m['players'])==3 and m['canStart'])
  n=len(h.messages);gn=len(g.messages);await h.send(type='rename_local',target=1,member=local['member'],name='NOVA')
  ack=await h.wait(lambda m:m['type']=='renamed',after=n)
  check(ack['id']==1 and ack['member']==local['member'] and ack['name']=='NOVA','Private secondary rename acknowledgement identifies current member')
  rr=await g.wait(lambda m:m['type']=='room' and m['players'][1]['name']=='NOVA',after=gn)
  check(rr['players'][2]['ready'] and rr['canStart'],'Local rename broadcasts without clearing guest readiness')
  check(not any(m['type']=='renamed' for m in g.messages[gn:]),'Secondary rename acknowledgement is not broadcast to other controllers')
  for op,label in [(dict(target=1,member=local['member']), 'Guest cannot rename another controller local'),(dict(target=0,member=r['players'][0]['member']),'Local rename cannot rename a primary human')]:
   n=len(g.messages);await g.send(type='rename_local',name='FORGED',**op);e=await g.wait(lambda m:m['type']=='error',after=n);check(e['code']=='not_owner' and e['action']=='rename_local',label)
  n=len(h.messages);await h.send(type='rename_local',target=1,member=local['member']+100,name='STALE');e=await h.wait(lambda m:m['type']=='error',after=n);check(e['code']=='player_missing','Stale member cannot rename a replacement local seat')
  n=len(h.messages);await h.send(type='rename_local',target=1,member=local['member'],name='<🌟>');e=await h.wait(lambda m:m['type']=='error',after=n);check(e['code']=='bad_name','Empty sanitized secondary name rejected')
  await asyncio.sleep(1.1)
  await h.send(type='start');s=await h.wait(lambda m:m['type']=='state' and m['phase']=='playing')
  n=len(h.messages);await h.send(type='rename_local',target=1,member=local['member'],name='雪 FOX');await h.wait(lambda m:m['type']=='renamed' and m['name']=='雪 FOX',after=n)
  s2=await h.wait(lambda m:m['type']=='state' and m['generation']==s['generation'] and any(t['id']==1 and t['name']=='雪 FOX' for t in m['tanks']),after=n)
  check(s2['round']==s['round'] and s2['scores']==s['scores'],'Live secondary rename updates authoritative tank without a match restart')
  await h.close();await asyncio.sleep(.15)
  h2=await peer();await h2.send(type='join',code=code,token=welcome['token']);await h2.wait(lambda m:m['type']=='welcome' and m['resumed'])
  rr=await h2.wait(lambda m:m['type']=='room');check(rr['players'][1]['name']=='雪 FOX','Secondary name survives authenticated controller reconnect')
  n=len(h2.messages);await h2.send(type='rename_local',target=1,member=local['member'],name='RESUMED');await h2.wait(lambda m:m['type']=='renamed' and m['name']=='RESUMED',after=n)
  check(True,'Original controller can rename its local pilot after host handoff')
  check(rr['host']==2,'Host handoff does not transfer secondary controller ownership')
  report={'version':'3.1.0','checks_passed':len(checks),'checks':checks,'handler':'normal production HTTP/WebSocket over loopback TCP'}
  (Path(__file__).parent/'results/gameplay-protocol-v3.1.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

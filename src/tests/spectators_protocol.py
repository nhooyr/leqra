"""v3.3 spectators through the production HTTP/WebSocket handler, no fixtures.
Run python tests/spectators_protocol.py http://127.0.0.1:8080.
"""
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
 async def op(p,typ,predicate=None,**args):
  n=len(p.messages);await p.send(type=typ,**args)
  return await p.wait(predicate or (lambda m:m['type']=='room'),after=n)
 async def error(p,typ,**args):return await op(p,typ,lambda m:m['type']=='error',**args)
 async def watch(code,name):
  p=await peer();w=await op(p,'join',lambda m:m['type']=='welcome',code=code,name=name,spectating=True);return p,w
 def own(r,id):return next(p for p in r['players']+r['spectators'] if p['id']==id)
 try:
  h=await peer();code='Spectators '+secrets.token_hex(6)+' 💥'
  roster=[dict(kind='human',name='HOST',team=1),dict(kind='local',name='LOCAL2',team=1),dict(kind='bot',name='BOT A',team=2,difficulty='easy'),dict(kind='bot',name='BOT B',team=2,difficulty='hard')]
  w=await op(h,'publish',lambda m:m['type']=='welcome',code=code,roster=roster)
  r=await h.wait(lambda m:m['type']=='room' and len(m['players'])==4);check(r['canStart'],'Four-seat mixed room starts without remote ready votes')
  blank=await peer();e=await error(blank,'join',code=code,name=' ',spectating=True);check(e['code']=='bad_name','Watch join requires nonempty accepted callsign at server')
  v,vw=await watch(code,'WATCHER');r=await v.wait(lambda m:m['type']=='room')
  check(vw['spectating'] and vw['id']>=4 and len(r['players'])==4 and len(r['spectators'])==1,'Watcher is separate member outside four combat seats')
  overflow=await peer();ow=await op(overflow,'join',lambda m:m['type']=='welcome',code=code,name='OVERFLOW');check(ow['spectating'] and ow['full'],'Regular full-room join falls back to spectator')
  r=await h.wait(lambda m:m['type']=='room' and len(m['spectators'])==2);check(r['canStart'],'Spectators do not prevent match start or require readiness')
  check(all('token' not in p and 'Controller' not in p for p in r['players']+r['spectators']),'Both member lists omit credentials and internal controller pointers')
  for typ,payload in [('spectate',dict(target=0,member=r['players'][0]['member'],spectating=True)),('swap',dict(target=0,member=r['players'][0]['member'],spectator=vw['id'],spectatorMember=vw['member'])),('kick',dict(target=0,member=r['players'][0]['member']))]:
   e=await error(v,typ,**payload);check(e['code'] in ['not_host','not_owned'],'Spectator cannot forge '+typ+' authority over others')
  e=await error(v,'spectate',spectating=False);check(e['code']=='no_seat','Full-room promotion fails without evicting a tank')
  n=len(v.messages);await h.send(type='start');s=await v.wait(lambda m:m['type']=='state' and m['phase']=='playing',after=n,timeout=9)
  check(len(s['tanks'])==4 and not any(t['id']==vw['id'] for t in s['tanks']),'Spectator receives live world without a spectator tank')
  await v.send(type='input',seq=1,fire=True,forward=True);e=await error(v,'input',player=0,seq=2,fire=True);check(e['code']=='not_owned','Watcher cannot control a tank through forged gameplay input')
  n=len(v.messages);await v.send(type='rename',name='NEW WATCHER');m=await v.wait(lambda m:m['type']=='renamed',after=n);check(m['name']=='NEW WATCHER','Spectator can rename themselves while watching')
  await asyncio.sleep(1.05)
  r=await op(h,'swap',target=1,member=r['players'][1]['member'],spectator=vw['id'],spectatorMember=vw['member'])
  check(own(r,1)['name']=='NEW WATCHER' and own(r,vw['id'])['kind']=='local','Host can exchange viewer with active local player')
  identity=await v.wait(lambda m:m['type']=='identity' and not m['spectating']);check(identity['id']==1 and identity['member']==vw['member'],'Role identity changes tank slot but not membership')
  s=await v.wait(lambda m:m['type']=='state' and any(t['id']==1 and t['name']=='NEW WATCHER' for t in m['tanks']))
  check(not next(t for t in s['tanks'] if t['id']==1)['alive'],'Incoming mid-round elimination player waits for next round')
  r=await op(v,'spectate',spectating=True);vid=next(p['id'] for p in r['spectators'] if p['name']=='NEW WATCHER')
  check(not any(p['id']==1 for p in r['players']) and vid>=4,'Active player voluntarily frees tank seat to watch')
  r=await op(v,'spectate',spectating=False);check(any(p['name']=='NEW WATCHER' for p in r['players']),'Watcher can join an available tank seat')
  await op(v,'spectate',spectating=True);r=await op(h,'lobby');check(len(r['spectators'])==3,'Returning entire game to lobby retains watchers including local P2')
  await asyncio.sleep(1.05);n=len(v.messages);await h.send(type='start');s=await v.wait(lambda m:m['type']=='state' and m['phase']=='playing',after=n,timeout=9)
  check(len(s['tanks'])==3 and not any(t['name']=='NEW WATCHER' for t in s['tanks']),'New game does not auto-promote previous spectators')
  r=await op(v,'spectate',spectating=True);vid=next(p['id'] for p in r['spectators'] if p['name']=='NEW WATCHER')
  await v.close();await asyncio.sleep(.12);v2=await peer();rw=await op(v2,'join',lambda m:m['type']=='welcome',code=code,token=vw['token']);check(rw['resumed'] and rw['spectating'] and rw['id']==vid,'Reconnect restores watch role despite omitted role hint')
  r=await op(h,'kick',target=rw['id'],member=rw['member']);removed=await v2.wait(lambda m:m['type']=='kicked');check(removed['room']==code and not any(p['id']==rw['id'] for p in r['spectators']),'Host can kick viewers during play and broadcast removal')
  revoked=await peer();e=await op(revoked,'join',lambda m:m['type'] in ['welcome','kicked','error'],code=code,token=vw['token']);check(e['type']=='kicked','Revoked watcher reconnect credential cannot bypass kick')
  # Swapping the host does not give their powers to the replacement pilot.
  await asyncio.sleep(1.05);r=await op(h,'swap',target=0,member=w['member'],spectator=ow['id'],spectatorMember=ow['member'])
  hi=await h.wait(lambda m:m['type']=='identity' and m['spectating']);check(r['host']==hi['id'] and own(r,0)['name']=='OVERFLOW','Host remains host after swapping their own tank with viewer')
  r=await op(h,'lobby');check(r['host']==hi['id'],'Watching host can end match and edit room')
  e=await error(overflow,'lobby');check(e['code']=='not_host','Former spectator taking host tank does not inherit authority')
  # Gallery bound is independent of combat seats and does not orphan a join.
  empty=await peer();cw=await op(empty,'join',lambda m:m['type']=='welcome',code='Viewer only '+secrets.token_hex(5),name='WATCH HOST',spectating=True)
  er=await empty.wait(lambda m:m['type']=='room');check(cw['created'] and cw['id']==er['host'] and not er['players'],'Missing room watch link can create a watching host')
  for i in range(15):await watch(cw['room'],'V '+str(i))
  extra=await peer();e=await error(extra,'join',code=cw['room'],name='TOO MANY',spectating=True);check(e['code']=='room_capacity','Spectator capacity is enforced with clear separate limit')
  ar=await op(extra,'join',lambda m:m['type']=='welcome',code=cw['room'],name='TANK');check(not ar['spectating'],'Full gallery does not prevent taking free combat seat')
  report={'version':'3.3.0','checks_passed':len(checks),'checks':checks,'handler':'production HTTP/WebSocket, normal origin validation, no fixtures'}
  (Path(__file__).parent/'results/spectators-protocol-v3.3.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':len(checks)}))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

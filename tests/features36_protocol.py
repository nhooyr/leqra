"""v3.6: live production handler checks. Run python tests/features36_protocol.py http://127.0.0.1:8080."""
import asyncio,json,secrets
from pathlib import Path
from urllib.request import urlopen
import protocol_smoke as wire
async def main():
 peers=[];checks=[]
 def check(v,s):
  assert v,s
  checks.append(s);print('PASS',s,flush=True)
 async def peer():
  p=await wire.peer();peers.append(p);return p
 async def op(p,typ,predicate=None,**kw):
  n=len(p.messages);await p.send(type=typ,**kw);return await p.wait(predicate or (lambda m:m['type']=='room'),after=n)
 async def error(p,typ,**kw):return await op(p,typ,lambda m:m['type']=='error',**kw)
 async def say(p,text,**kw):return await op(p,'chat',lambda m:m['type'] in ['chat','error'],text=text,**kw)
 try:
  cfg=json.load(urlopen(wire.BASE+'/api/config'));health=json.load(urlopen(wire.BASE+'/healthz'));check(health['version']=='3.7.1','Production reports version 3.7.1');check(cfg['maxPlayers']==8,'API advertises eight tank seats')
  host=await peer();w=await op(host,'create',lambda m:m['type']=='welcome',name='HOST');code=w['room'];players=[host];identities=[w]
  r=await host.wait(lambda m:m['type']=='room');check(r['rules']['teamMode']=='ffa' and r['players'][0]['team']==0,'New room defaults to global Free-for-all')
  check(r['rules']['teamNames']==['Team 1','Team 2','Team 3','Team 4'],'Four default team names in room snapshot')
  names=[' Alpha 🌟 ','<b>Fire</b>','水','💥'*24];named=r['rules'].copy();named.update(teamMode='teams',teamNames=names)
  r=await op(host,'rules',rules=named);check(r['rules']['teamNames']==[n.strip() for n in names],'Host names normalize and round-trip Unicode/literal markup')
  e=await error(host,'configure',target=w['id'],member=w['member'],team=0);check(e['code']=='bad_team','No Independent seat assignment in Teams')
  e=await error(host,'add',kind='bot',difficulty='normal',team=0);check(e['code']=='bad_team','No Independent bot in Teams')
  invalid=named.copy();invalid['teamNames']=['Bad\nName','B','C','D'];e=await error(host,'rules',rules=invalid);check(e['code']=='bad_rules','Reject malformed team names atomically')
  invalid['teamNames']=[];e=await error(host,'rules',rules=invalid);check(e['code']=='bad_rules','Reject explicit empty team-name list')
  for i in range(1,8):
   p=await peer();pw=await op(p,'join',lambda m:m['type']=='welcome',code=code,name='P'+str(i));players.append(p);identities.append(pw);check(pw['id']==i and not pw['spectating'],'Tank seat '+str(i)+' assigned')
  check(len({w['token'] for w in identities})==8,'Eight private reconnect credentials')
  r=await host.wait(lambda m:m['type']=='room' and len(m['players'])==8);check(r['rules']['mapSize']=='large','Shared default map 12x10')
  viewer=await peer();vw=await op(viewer,'join',lambda m:m['type']=='welcome',code=code,name='VIEWER');check(vw['spectating'] and vw['full'] and vw['id']>=8,'Ninth join falls back to watcher')
  watching=await peer();ww=await op(watching,'join',lambda m:m['type']=='welcome',code=code,name='WATCH LINK',spectating=True);check(ww['spectating'],'Explicit watcher remains spectator')
  outsider=await peer();ow=await op(outsider,'create',lambda m:m['type']=='welcome',name='OUTSIDER')
  guestRules=r['rules'].copy();guestRules['teamNames']=['Stolen','B','C','D'];e=await error(players[7],'rules',rules=guestRules);check(e['code']=='not_host','Guest cannot rename the four teams')
  e=await error(players[7],'start');check(e['code']=='not_host','Seat seven cannot start as guest')
  rules=r['rules'].copy();rules.update(mapSize='huge',mode='koth',timeLimit=600,scoreTarget=300)
  e=await error(viewer,'rules',rules=rules);check(e['code']=='not_host','Spectator cannot change rules')
  r=await op(host,'rules',rules=rules);check(r['rules']['mapSize']=='huge','Host can choose 14x12');check(r['rules']['teamNames']==[n.strip() for n in names],'Map/mode changes preserve team names')
  readyFrom=len(host.messages)
  for p in players[1:]:await p.send(type='ready',ready=True)
  await host.wait(lambda m:m['type']=='room' and m['canStart'],after=readyFrom);await host.send(type='start');world=await host.wait(lambda m:m['type']=='state' and m.get('world',{}).get('cols')==14)
  check(world['world']['rows']==12 and len(world['tanks'])==8,'14x12 authoritative world has eight tanks')
  initial={(t['x'],t['y']) for t in world['tanks']};check(len(initial)==8,'Eight distinct server spawn positions')
  for p in [players[7],viewer,watching]:
   s=await p.wait(lambda m:m['type']=='state' and m.get('world',{}).get('cols')==14);check(s['world']==world['world'],'High seat/viewer receives same world')
  await host.wait(lambda m:m['type']=='state' and m['phase']=='playing')
  n=len(host.messages);await players[7].send(type='input',seq=91,right=True,fire=True,x=99999,y=-3)
  s=await host.wait(lambda m:m['type']=='state' and any(t['id']==7 and t['ack']==91 for t in m['tanks']),after=n);t=next(t for t in s['tanks'] if t['id']==7);check(0<t['x']<world['world']['width'] and 0<t['y']<world['world']['height'],'Top seat accepts controls, ignores forged coordinates')
  e=await error(viewer,'input',player=7,seq=92,fire=True);check(e['code']=='not_owned','Spectator cannot drive seat seven')
  await players[7].send(type='input',seq=92)
  m=await say(players[7],'Hello room 💥',name='SPOOF',member=w['member'],spectating=True);check(m['type']=='chat' and m['message']['name']=='P7' and m['message']['member']==identities[7]['member'],'Chat author cannot be spoofed')
  for p in [host,players[1],viewer,watching]:
   got=await p.wait(lambda x:x['type']=='chat' and x['message']['text']=='Hello room 💥');check(not got['message']['spectating'],'All members receive player role chat')
  check(not any(m['type']=='chat' for m in outsider.messages),'No cross-room chat leak')
  m=await say(viewer,'Spectators can chat');check(m['message']['spectating'] and m['message']['name']=='VIEWER','Spectator chat is attributed and accepted during play')
  await say(watching,'<script>not HTML</script>');m=await say(watching,'💥'*280);check(m['type']=='chat' and len(m['message']['text'])==280,'280 Unicode codepoints accepted')
  for bad in ['','\u200b','x\ny','💥'*281]:
   e=await say(outsider,bad);check(e['type']=='error' and e['code']=='bad_chat','Reject invalid chat '+repr(bad[:8]))
  await asyncio.sleep(1.1)
  for i in range(4):
   m=await say(outsider,'burst '+str(i));check(m['type']=='chat','Initial chat burst '+str(i))
  e=await say(outsider,'too fast');check(e['code']=='chat_rate','Chat flood is rate limited');await asyncio.sleep(1.1);m=await say(outsider,'after refill');check(m['type']=='chat','Rate limit recovers without disconnect')
  # Role transitions and new matches retain the same room history.
  await asyncio.sleep(1.05);r=await op(host,'lobby');check(len(r['players'])==8 and len(r['spectators'])==2,'Back to lobby preserves expanded lineup and watchers')
  readyFrom=len(host.messages)
  for p in players[1:]:await p.send(type='ready',ready=True)
  await host.wait(lambda m:m['type']=='room' and m['canStart'],after=readyFrom);await host.send(type='start');await host.wait(lambda m:m['type']=='state' and m['phase']=='countdown',after=len(host.messages)-1)
  late=await peer();lw=await op(late,'join',lambda m:m['type']=='welcome',code=code,name='LATE');hist=await late.wait(lambda m:m['type']=='chat_history');check(lw['spectating'] and len(hist['messages'])==4,'New spectator receives history across games')
  check([m['id'] for m in hist['messages']]==[1,2,3,4],'Chat IDs ordered and room-local');raw=json.dumps(hist);check(all(x['token'] not in raw for x in identities),'No reconnect credentials in chat history')
  oldtoken=vw['token'];await viewer.close();await asyncio.sleep(.15);resume=await peer();rw=await op(resume,'join',lambda m:m['type']=='welcome',code=code,token=oldtoken);hist=await resume.wait(lambda m:m['type']=='chat_history');check(rw['resumed'] and rw['spectating'] and len(hist['messages'])==4,'Reconnect restores spectator and chat history')
  await asyncio.sleep(1.05);r=await op(host,'kick',target=rw['id'],member=rw['member']);k=await resume.wait(lambda m:m['type']=='kicked');check(k['room']==code,'Host can kick a chatting spectator');revoked=await peer();x=await op(revoked,'join',lambda m:m['type'] in ['kicked','welcome','error'],code=code,token=oldtoken);check(x['type']=='kicked','Kicked spectator token cannot rejoin for chat')
  # High-seat member can become a spectator, retaining host-safe tank counts.
  r=await op(players[7],'spectate',spectating=True);check(len(r['players'])==7 and any(m['name']=='P7' for m in r['spectators']),'Seat seven can switch to spectating')
  msg=await say(players[7],'Now watching');check(msg['message']['spectating'],'Chat updates role after switching')
  e=await error(watching,'kick',target=0,member=w['member']);check(e['code']=='not_host','Spectator cannot kick chat peers')
  check(all(len(s.get('scores',[]))==8 for s in host.messages if s['type']=='state'),'Every state has eight score slots')
  report={'version':'3.7.1','passed':len(checks),'checks':checks,'handler':'Production HTTP/WebSocket with normal origin validation; no fixture endpoints.'};(Path(__file__).parent/'results/features36-protocol.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

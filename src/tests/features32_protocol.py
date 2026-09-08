"""v3.2 host rules/presets/FFA/objective protocol checks through production HTTP.
Run: python tests/features32_protocol.py http://127.0.0.1:8080
No fixture endpoints are used.
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
 async def error(p,**op):
  n=len(p.messages);await p.send(**op);return await p.wait(lambda m:m['type']=='error',after=n)
 def rules(**kw):return dict(mode='elimination',teamMode='teams',mapSize='compact',scoreTarget=3,timeLimit=40,respawnSeconds=2,pickupRate='off',weapons=['laser','shield'],**kw) if not kw else {**rules(),**kw}
 roster=[dict(kind='human',name='HOST',team=1),dict(kind='local',name='P2',team=1),dict(kind='bot',name='RUST',team=2,difficulty='easy')]
 try:
  h=await peer();code='RULES32 '+secrets.token_hex(5)
  await h.send(type='publish',code=code,roster=roster,rules=rules(mode='ctf'))
  welcome=await h.wait(lambda m:m['type']=='welcome');r=await h.wait(lambda m:m['type']=='room' and m['rules']['mode']=='ctf')
  check(r['rules']['mode']=='ctf' and r['rules']['mapSize']=='compact','Publication imports configured objective rules')
  g=await peer();await g.send(type='join',code=code,name='GUEST');gw=await g.wait(lambda m:m['type']=='welcome');r=await h.wait(lambda m:m['type']=='room' and len(m['players'])==4)
  check(r['players'][gw['id']]['team']==2,'New online guest balances into existing team rather than third side')
  e=await error(g,type='rules',rules=rules(teamMode='ffa'));check(e['code']=='not_host' and e['action']=='rules','Non-host cannot enable FFA through forged command')
  e=await error(g,type='preset',rules=rules(),roster=roster);check(e['code']=='not_host','Non-host cannot replace lineup using a preset')
  e=await error(h,type='preset',rules=rules(),roster=roster);check(e['code']=='guests_present','Host preset cannot evict active remote guests')
  await g.send(type='ready',ready=True);await h.wait(lambda m:m['type']=='room' and m['canStart'])
  n=len(h.messages);await h.send(type='rules',rules=rules(teamMode='ffa'));r=await h.wait(lambda m:m['type']=='room' and m['rules']['teamMode']=='ffa',after=n)
  check(all(p['team']==0 for p in r['players']),'Host FFA rule clears all seat teams atomically')
  check(not r['players'][gw['id']]['ready'],'Rule changes clear online guest readiness')
  s=r['players'][1];e=await error(h,type='configure',target=s['id'],member=s['member'],team=3);check(e['code']=='teams_locked','Even host per-seat team edits are locked until FFA is disabled')
  n=len(h.messages);await h.send(type='rules',rules=rules(mode='ctf',teamMode='ffa'));e=await h.wait(lambda m:m['type']=='error',after=n);check(e['code']=='bad_rules','CTF cannot run with Free-for-all')
  e=await error(h,type='rules',rules=rules(scoreTarget=999));check(e['code']=='bad_rules','Server rejects client-supplied rule values beyond bounds')
  n=len(h.messages);await h.send(type='rules',rules=rules(mode='ctf'));r=await h.wait(lambda m:m['type']=='room' and m['rules']['mode']=='ctf',after=n)
  check(r['players'][0]['team']==1 and r['players'][1]['team']==1 and r['players'][2]['team']==2 and r['players'][3]['team']==2,'Leaving FFA restores two controller-aware teams')
  await g.send(type='ready',ready=True);await h.wait(lambda m:m['type']=='room' and m['canStart'],after=n);await asyncio.sleep(1.05);await h.send(type='start');s=await h.wait(lambda m:m['type']=='state' and m['phase']=='playing',timeout=9)
  check(s['rules']['mode']=='ctf' and len(s['objectives']['flags'])==2,'Production CTF snapshot contains both server-owned flags')
  maps=[m for m in h.messages if m['type']=='state' and m.get('world')];check(maps[-1]['world']['cols']==7 and maps[-1]['world']['rows']==7,'Production maze dimensions respect map rule')
  check(s['roundClock']<=40 and not s['pickups'],'Production clock and pickup-off setting applied')
  e=await error(h,type='rules',rules=rules());check(e['code']=='match_active','Even host cannot change match rules during play')
  rogue=await peer();await rogue.send(type='objective',scores=[300]*4,flags=[],mode='koth');await asyncio.wait_for(rogue.ws.wait_closed(),3);check(rogue.ws.close_code==1008,'Client cannot submit objective score or flag state')
  n=len(h.messages);await h.send(type='input',player=0,seq=1,forward=True,fire=True,score=999,flags=[],rules=rules(mode='koth'));await asyncio.sleep(.12);s=await h.wait(lambda m:m['type']=='state',after=n);check(s['rules']['mode']=='ctf' and all(v<3 for v in s['scores']),'Forged state attached to input is ignored')
  n=len(h.messages);await h.send(type='lobby');r=await h.wait(lambda m:m['type']=='room' and m['phase']=='lobby',after=n);check(r['rules']['mode']=='ctf','End match retains configured rules')
  await g.send(type='leave');await h.wait(lambda m:m['type']=='room' and len(m['players'])==3,after=n)
  n=len(h.messages);await h.send(type='preset',rules=rules(mode='koth',teamMode='ffa',scoreTarget=15,timeLimit=60),roster=roster);r=await h.wait(lambda m:m['type']=='room' and m['rules']['mode']=='koth',after=n)
  check(r['host']==welcome['id'] and all(p['team']==0 for p in r['players']),'Host-only preset atomically loads KOTH/FFA without changing host')
  await asyncio.sleep(1.05);await h.send(type='start');s=await h.wait(lambda m:m['type']=='state' and m['phase']=='playing' and m['rules']['mode']=='koth',after=n,timeout=9)
  check(s['objectives']['mode']=='koth' and s['objectives']['radius']>0,'Production KOTH snapshot includes authoritative hill')
  oldtoken=welcome['token'];await h.close();h2=await peer();await h2.send(type='join',code=code,token=oldtoken);w=await h2.wait(lambda m:m['type']=='welcome');r=await h2.wait(lambda m:m['type']=='room');check(w['resumed'] and r['rules']['mode']=='koth','Reconnect restores objective room and configured rules')
  report={'version':'3.2.0','checks_passed':len(checks),'checks':checks,'handler':'production HTTP/WebSocket with normal origin validation; no test fixture'}
  (Path(__file__).parent/'results/features-protocol-v3.2.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

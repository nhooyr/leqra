"""Ghost/Cannon v4.1 production admission, settings, spawn and authority checks."""
import asyncio,json,os
from pathlib import Path
from urllib.request import urlopen
from urllib.error import HTTPError
import protocol_smoke as wire
VERSION=os.environ.get('LEQRA_EXPECT_VERSION','4.1.0')
async def main():
 checks=[];peers=[]
 def check(ok,label):assert ok,label;checks.append(label);print('PASS',label,flush=True)
 async def peer():p=await wire.peer();peers.append(p);return p
 async def op(p,kind,predicate=None,**kw):
  n=len(p.messages);await p.send(type=kind,**kw);return await p.wait(predicate or (lambda m:m['type']=='room'),after=n)
 try:
  check(json.load(urlopen(wire.BASE+'/healthz'))['version']==VERSION,'Production version '+VERSION)
  for path in ['/_fixture/cannon39','/_fixture/scope38','/_fixture/phase41','/_fixture/combat42']:
   try:urlopen(wire.BASE+path);check(False,'Fixture absent '+path)
   except HTTPError as e:check(e.code==404,'Production has no '+path+' endpoint')
  host=await peer();welcome=await op(host,'create',lambda m:m['type']=='welcome',name='HOST');code=welcome['room'];r=await host.wait(lambda m:m['type']=='room')
  check('cannon' in r['rules']['weapons'] and 'ghost' in r['rules']['weapons'] and len(r['rules']['weapons'])==10,'Default rules advertise ten pickups including Ghost and Cannon')
  guest=await peer();await op(guest,'join',lambda m:m['type']=='welcome',code=code,name='GUEST')
  viewer=await peer();v=await op(viewer,'join',lambda m:m['type']=='welcome',code=code,name='WATCHER',spectating=True)
  check(v['spectating'],'Cannon update retains spectator admission')
  rules=r['rules'].copy();rules.update(weapons=['ghost'],mode='koth',timeLimit=600,scoreTarget=300)
  for p,name in [(guest,'Guest'),(viewer,'Spectator')]:
   e=await op(p,'rules',lambda m:m['type']=='error',rules=rules);check(e['code']=='not_host',name+' cannot enable or disable weapons')
  r=await op(host,'rules',rules=rules);check(r['rules']['weapons']==['ghost'],'Host can select Ghost-only rules')
  bad={**rules,'weapons':['ghost','ghost']};e=await op(host,'rules',lambda m:m['type']=='error',rules=bad);check(e['code']=='bad_rules','Duplicate Ghost rule rejected')
  await guest.send(type='ready',ready=True);await host.wait(lambda m:m['type']=='room' and m['canStart']);n=len(host.messages);await host.send(type='start')
  s=await host.wait(lambda m:m['type']=='state' and m['phase']=='countdown' and m.get('world'),after=n)
  check(s['world']['cols']==12 and s['world']['rows']==10,'12x10 default remains unchanged')
  check(len(s['pickups'])==4 and all(p['type']=='ghost' for p in s['pickups']),'Four genuine Ghost pickups seeded by server')
  for p,name in [(guest,'Guest'),(viewer,'Spectator')]:
   seen=await p.wait(lambda m:m['type']=='state' and m['phase']=='countdown' and m.get('world'))
   check(seen['pickups']==s['pickups'],name+' receives identical authoritative Ghost pickups')
  s=await host.wait(lambda m:m['type']=='state' and m['phase']=='playing' and len(m['pickups'])==5,timeout=6)
  check(.99<=600-s['roundClock']<=1.13,'Super fast first-second spawn boundary retained')
  n=len(host.messages);await host.send(type='input',room=code,seq=90,fire=True,power='cannon',ghostTime=999,charges=999,speed=999,r=999,kind='cannon');s=await host.wait(lambda m:m['type']=='state' and any(t['ack']==90 for t in m['tanks']),after=n)
  check(next(t for t in s['tanks'] if t['id']==welcome['id'])['power']=='','Forged Cannon grant ignored')
  check(next(t for t in s['tanks'] if t['id']==welcome['id'])['ghostTime']==0,'Client cannot grant Ghost or wall movement')
  owned=[b for b in s['bullets'] if b['owner']==welcome['id']]
  check(owned and all(b.get('kind','')=='' and b['r']==3.5 and abs((b['vx']**2+b['vy']**2)**.5-282)<.001 for b in owned),'Unpowered pilot fires only genuine normal-speed/size rounds')
  await host.send(type='input',room=code,seq=91,fire=False)
  e=await op(host,'rules',lambda m:m['type']=='error',rules=rules);check(e['code']=='match_active','Weapon rules stay locked during play')
  report={'version':VERSION,'passed':len(checks),'checks':checks,'handler':'Production HTTP/WebSocket handler; no fixture or grants.'}
  (Path(__file__).parent/('results/phase41-protocol-v'+VERSION+'.json')).write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

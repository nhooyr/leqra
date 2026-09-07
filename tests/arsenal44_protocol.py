"""Production endpoint checks: palette authority, snapshot compatibility and pickups.
Run against a real production Go binary: python tests/arsenal44_protocol.py URL
"""
import asyncio,json
from pathlib import Path
from urllib.request import urlopen
from urllib.error import HTTPError
import protocol_smoke as wire
async def main():
 checks=[];peers=[]
 def check(ok,label):
  assert ok,label
  checks.append(label);print('PASS',label,flush=True)
 async def peer():
  p=await wire.peer();peers.append(p);return p
 async def op(p,kind,pred=None,**kw):
  # Respect the production eight-actions/second budget during validation probes.
  await asyncio.sleep(.18)
  n=len(p.messages);await p.send(type=kind,**kw);return await p.wait(pred or (lambda s:s['type']=='room'),after=n)
 try:
  check(json.load(urlopen(wire.BASE+'/healthz'))['version']=='4.4.0','Production binary reports 4.4.0')
  for path in ['/_fixture/arsenal44','/_fixture/combat42']:
   try:urlopen(wire.BASE+path);check(False,'Fixture accidentally exposed')
   except HTTPError as e:check(e.code==404,'No production '+path+' endpoint')
  host=await peer();hello=await op(host,'create',lambda s:s['type']=='welcome',name='HOST');code=hello['room'];r=await host.wait(lambda s:s['type']=='room');check(r['rules']['teamColors']==[0,1,2,3],'Four backward-compatible default team colors')
  guest=await peer();gh=await op(guest,'join',lambda s:s['type']=='welcome',name='FRIEND',code=code)
  viewer=await peer();vh=await op(viewer,'join',lambda s:s['type']=='welcome',name='WATCHER',code=code,spectating=True);check(vh['spectating'],'Spectator can observe styled room')
  r=await host.wait(lambda s:s['type']=='room' and len(s['players'])==2 and len(s['spectators'])==1);target=next(p for p in r['players'] if p['id']==gh['id']);gid=target['id'];member=target['member']
  for who,label in [(guest,'guest'),(viewer,'spectator')]:
   e=await op(who,'configure',lambda s:s['type']=='error',target=gid,member=member,colorIndex=7);check(e['code']=='not_host',label+' cannot forge tank palette changes')
  for invalid in [-2,8,99]:
   e=await op(host,'configure',lambda s:s['type']=='error',target=gid,member=member,colorIndex=invalid);check(e['code']=='bad_color','Out-of-palette index rejected: '+str(invalid))
  rules=r['rules'].copy();rules.update(teamMode='teams',teamColors=[6,4,3,7],weapons=['shield'],pickupRate='superfast')
  bad={**rules,'teamColors':[0,1,2,8]};e=await op(host,'rules',lambda s:s['type']=='error',rules=bad);check(e['code']=='bad_rules','Invalid team palette rejected atomically')
  r=await op(host,'rules',rules=rules);check(r['rules']['teamColors']==[6,4,3,7],'Host-selected team palette broadcast')
  r=await op(host,'configure',target=gid,member=member,colorIndex=5);p=next(p for p in r['players'] if p['id']==gid);check(p['colorIndex']==5 and p['color']=='#ff83bd','Host can recolor remote tank separately from its team')
  gr=await guest.wait(lambda s:s['type']=='room' and any(p.get('colorIndex')==5 for p in s['players']));check(any(p['id']==gid and p['color']=='#ff83bd' for p in gr['players']),'Guest receives canonical selection, independent of skin')
  await op(guest,'ready',ready=True);await host.wait(lambda s:s['type']=='room' and s['canStart']);n=len(host.messages);await host.send(type='start');s=await host.wait(lambda s:s['type']=='state' and s['phase']=='countdown' and s.get('world'),after=n)
  check(len(s['pickups'])==4 and all(p['type']=='shield' for p in s['pickups']),'Host weapon filter still governs real spawned pickups')
  tanks={p['id']:p for p in s['tanks']};check(tanks[gid]['color']=='#ff83bd' and tanks[hello['id']]['color']=='#75f0cb','Spawn respects tank override and team inherited color')
  check(all(t['shieldCharges']==0 and t['shield']==0 for t in s['tanks']),'Fresh game has no phantom shield stacks')
  check(s['rules']['teamColors']==rules['teamColors'],'State carries authoritative team colors')
  e=await op(host,'configure',lambda s:s['type']=='error',target=gid,member=member,colorIndex=2);check(e['code']=='match_active','Palette editing locked during active game')
  s=await host.wait(lambda s:s['type']=='state' and s['phase']=='playing',timeout=6)
  n=len(host.messages);await host.send(type='input',room=code,seq=551,fire=True,power='rapid',shield=999,shieldCharges=999,colorIndex=7,r=999)
  s=await host.wait(lambda s:s['type']=='state' and any(t['ack']==551 for t in s['tanks']),after=n)
  tank=next(t for t in s['tanks'] if t['id']==hello['id']);check(tank['power']=='' and tank['shieldCharges']==0 and tank['color']=='#75f0cb','Inputs cannot grant weapons, shields or colors')
  check(all(abs(b['r']-3.5)<1e-9 for b in s['bullets'] if b['owner']==hello['id']),'Unpowered shots retain normal geometry')
  await host.send(type='input',room=code,seq=552,fire=False)
  check('machineBullets' not in s,'Compact stream omitted when no machine gun is equipped')
  report=dict(version='4.4.0',passed=len(checks),checks=checks,handler='Production Go HTTP/WebSocket, real sockets; no fixture grants.')
  (Path(__file__).parent/'results/v4.4/production-protocol.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:
  await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

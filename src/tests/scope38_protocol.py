"""v3.8 production HTTP/WebSocket integration. No fixture/grant endpoints."""
import asyncio,json
from pathlib import Path
from urllib.request import urlopen
import protocol_smoke as wire
async def main():
 checks=[];peers=[]
 def check(ok,s):
  assert ok,s
  checks.append(s);print('PASS',s,flush=True)
 async def peer():
  p=await wire.peer();peers.append(p);return p
 async def op(p,typ,predicate=None,**kw):
  n=len(p.messages);await p.send(type=typ,**kw);return await p.wait(predicate or (lambda m:m['type']=='room'),after=n)
 try:
  check(json.load(urlopen(wire.BASE+'/healthz'))['version']=='3.8.0','Production reports 3.8.0')
  for name,cols,rows,start,cap in [('compact',7,7,2,5),('standard',9,8,3,7),('large',12,10,4,12),('huge',14,12,5,17),('giant',16,14,6,23)]:
   host=await peer();w=await op(host,'create',lambda m:m['type']=='welcome',name='HOST');code=w['room'];r=await host.wait(lambda m:m['type']=='room')
   check(r['rules']['mapSize']=='large' and 'scope' in r['rules']['weapons'],name+': default large map with Scope available')
   guest=await peer();await op(guest,'join',lambda m:m['type']=='welcome',code=code,name='GUEST')
   viewer=await peer();vw=await op(viewer,'join',lambda m:m['type']=='welcome',code=code,name='WATCHER',spectating=True)
   rules=r['rules'].copy();rules.update(mapSize=name,weapons=['scope'],mode='koth',timeLimit=600,scoreTarget=300)
   e=await op(guest,'rules',lambda m:m['type']=='error',rules=rules);check(e['code']=='not_host',name+': guest cannot change map or Scope rules')
   r=await op(host,'rules',rules=rules);check(r['rules']['mapSize']==name and r['rules']['weapons']==['scope'],name+': host map/Scope-only settings accepted')
   await guest.send(type='ready',ready=True);await host.wait(lambda m:m['type']=='room' and m['canStart']);n=len(host.messages);await host.send(type='start')
   s=await host.wait(lambda m:m['type']=='state' and m['phase']=='countdown' and m.get('world'),after=n)
   check(s['world']['cols']==cols and s['world']['rows']==rows and len(s['pickups'])==start,name+': authoritative map dimensions and starting count')
   check(all(p['type']=='scope' for p in s['pickups']) and all(t['scopeTime']==0 for t in s['tanks']),name+': real Scope pickups and unbuffed snapshot timers')
   for p,label in [(guest,'guest'),(viewer,'spectator')]:
    seen=await p.wait(lambda m:m['type']=='state' and m.get('world') and m['phase']=='countdown')
    check(seen['world']==s['world'] and seen['pickups']==s['pickups'],name+': '+label+' receives the same map and pickup state')
   s=await host.wait(lambda m:m['type']=='state' and m['phase']=='playing' and len(m['pickups'])==start+1,timeout=6)
   check(.99<=600-s['roundClock']<=1.12,name+': first extra pickup remains one live second after start')
   n=len(host.messages);await guest.send(type='input',seq=21,scopeTime=999,power='scope');after=await host.wait(lambda m:m['type']=='state' and any(t['ack']==21 for t in m['tanks']),after=n)
   check(all(t['scopeTime']==0 and t['power']=='' for t in after['tanks']),name+': forged scope state is ignored')
   e=await op(host,'rules',lambda m:m['type']=='error',rules=rules);check(e['code']=='match_active',name+': live match keeps map/rules locked')
   for p in [host,guest,viewer]:await p.close()
  report={'version':'3.8.0','passed':len(checks),'checks':checks,'handler':'Production server, real WebSockets and ordinary origin validation; no fixture endpoints.'}
  (Path(__file__).parent/'results/scope38-protocol.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)
if __name__=='__main__':asyncio.run(main())

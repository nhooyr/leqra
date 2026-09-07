"""v3.7.2 live default-frequency/rules tests against the production WebSocket handler.
Run: python tests/defaults372_protocol.py http://127.0.0.1:18772
"""
import asyncio
import json
from pathlib import Path
from urllib.request import urlopen
import protocol_smoke as wire

async def main():
    peers,checks=[],[]
    def check(ok,label):
        assert ok,label
        checks.append(label);print('PASS',label,flush=True)
    async def peer():
        p=await wire.peer();peers.append(p);return p
    async def op(p,typ,predicate=None,**kw):
        n=len(p.messages);await p.send(type=typ,**kw)
        return await p.wait(predicate or (lambda m:m['type']=='room'),after=n)
    try:
        check(json.load(urlopen(wire.BASE+'/healthz'))['version']=='3.7.2','Production version 3.7.2')
        host=await peer();w=await op(host,'create',lambda m:m['type']=='welcome',name='HOST')
        room=await host.wait(lambda m:m['type']=='room')
        check(room['rules']['pickupRate']=='superfast','Go-created room defaults to Super fast')
        guest=await peer();await op(guest,'join',lambda m:m['type']=='welcome',code=w['room'],name='GUEST')
        viewer=await peer();vw=await op(viewer,'join',lambda m:m['type']=='welcome',code=w['room'],name='WATCHER',spectating=True)
        check(vw['spectating'],'Watcher keeps spectator role')
        for p in (guest,viewer):
            r=await p.wait(lambda m:m['type']=='room')
            check(r['rules']['pickupRate']=='superfast','Joined member receives Super fast rule')
        rules=room['rules'].copy();rules['pickupRate']='slow'
        e=await op(guest,'rules',lambda m:m['type']=='error',rules=rules)
        check(e['code']=='not_host','Guest cannot change spawn frequency')
        rules['pickupRate']='superfast'
        e=await op(viewer,'rules',lambda m:m['type']=='error',rules=rules)
        check(e['code']=='not_host','Spectator cannot change spawn frequency')
        for rate in ('fast','superfast'):
            rules['pickupRate']=rate;r=await op(host,'rules',rules=rules)
            check(r['rules']['pickupRate']==rate,'Host selects '+rate+' through live socket')
        rules['pickupRate']='invalid'
        e=await op(host,'rules',lambda m:m['type']=='error',rules=rules)
        check(e['code']=='bad_rules','Unknown spawn frequency is rejected')
        await guest.send(type='ready',ready=True)
        await host.wait(lambda m:m['type']=='room' and m['canStart'])
        n=len(host.messages);await host.send(type='start')
        initial=await host.wait(lambda m:m['type']=='state' and m['phase']=='countdown',after=n)
        check(len(initial['pickups'])==2,'Online match begins with two pickups')
        rules['pickupRate']='slow';e=await op(host,'rules',lambda m:m['type']=='error',rules=rules)
        check(e['code']=='match_active','Frequency remains locked during active match')
        await host.wait(lambda m:m['type']=='state' and m['phase']=='playing')
        first=await host.wait(lambda m:m['type']=='state' and len(m['pickups'])==3,timeout=4)
        # Simulation timestamps, not wall time, establish the first interval.
        clockkey='roundClock' if 'roundClock' in first else 'clock'
        elapsed=75-first[clockkey]
        check(.99<=elapsed<=1.12,'First additional online pickup after one simulation second')
        last=await host.wait(lambda m:m['type']=='state' and len(m['pickups'])==5,timeout=5)
        for p in (guest,viewer):
            s=await p.wait(lambda m:m['type']=='state' and m['tick']==last['tick'],timeout=3)
            check(s['pickups']==last['pickups'],'Player/spectator receives identical authoritative pickups')
        transitions=[];prev=2
        for s in host.messages:
            if s['type']!='state' or s['phase']!='playing':continue
            n=len(s['pickups'])
            if n>prev:
                transitions.append(75-s[clockkey]);prev=n
        check(len(transitions)==3,'Three scheduled additions reach five-pickup cap')
        check(all(.95<=b-a<=2.08 for a,b in zip(transitions,transitions[1:])),'Repeated online pickup intervals stay in 1–2s range')
        # Reconnection must retain the accepted room rule, not apply a client fallback.
        token=vw['token'];await viewer.close();await asyncio.sleep(.12)
        back=await peer();rw=await op(back,'join',lambda m:m['type']=='welcome',code=w['room'],token=token)
        r=await back.wait(lambda m:m['type']=='room')
        check(rw['resumed'] and rw['spectating'] and r['rules']['pickupRate']=='superfast','Reconnect preserves spectator role and frequency')
        report={'version':'3.7.2','passed':len(checks),'checks':checks,'spawnTimes':transitions,'handler':'Unmodified production HTTP/WebSocket handler, local loopback. No grant/map fixture endpoints.'}
        (Path(__file__).parent/'results/defaults-protocol-v3.7.2.json').write_text(json.dumps(report,indent=2))
        print('TOTAL',len(checks))
    finally:
        await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)

if __name__=='__main__':asyncio.run(main())

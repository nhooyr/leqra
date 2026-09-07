"""Optional live integration checks. Run a server, then:
python -m pip install websockets
python tests/protocol_smoke.py http://localhost:8080
No Python packages are needed to run the game itself.
"""
import asyncio
import json
import sys
import secrets
from urllib.parse import urlsplit
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed, InvalidStatus

BASE = sys.argv[1].rstrip('/') if len(sys.argv) > 1 else 'http://localhost:8080'
p = urlsplit(BASE)
ORIGIN = f'{p.scheme}://{p.netloc}'
WS = f'{"wss" if p.scheme == "https" else "ws"}://{p.netloc}/ws'
checks = []

def check(condition, name):
    assert condition, name
    checks.append(name)
    print('PASS', name)

class Peer:
    def __init__(self, ws):
        self.ws = ws
        self.messages = []
        self.task = asyncio.create_task(self.read())
    async def read(self):
        try:
            async for data in self.ws:
                self.messages.append(json.loads(data))
        except ConnectionClosed:
            pass
    async def send(self, **v):
        await self.ws.send(json.dumps(v))
    async def wait(self, predicate, after=0, timeout=7):
        async def poll():
            while True:
                for msg in self.messages[after:]:
                    if predicate(msg): return msg
                await asyncio.sleep(.01)
        return await asyncio.wait_for(poll(), timeout)
    async def close(self):
        await self.ws.close()
        await self.task

async def peer():
    return Peer(await connect(WS, origin=ORIGIN, max_size=1_000_000, compression=None))

async def main():
    peers = []
    try:
        for _ in range(6): peers.append(await peer())
        await peers[0].send(type='create', name='HOST')
        welcome = await peers[0].wait(lambda m:m['type']=='welcome')
        code = welcome['room']
        welcomes = [welcome]
        for i in range(1,4):
            await peers[i].send(type='join', code=code, name=f'PILOT {i}')
            welcomes.append(await peers[i].wait(lambda m:m['type']=='welcome'))
        check(len({m['id'] for m in welcomes})==4, 'Four unique player seats')
        check(len({m['token'] for m in welcomes})==4, 'Independent private reconnect credentials')
        await peers[4].send(type='join', code=code)
        viewer=await peers[4].wait(lambda m:m['type']=='welcome')
        check(viewer['spectating'] and viewer['full'] and viewer['id']>=4,'Fifth visitor enters as spectator')
        await peers[5].send(type='create',name='OTHER ROOM')
        other=await peers[5].wait(lambda m:m['type']=='welcome')
        check(other['room']!=code,'Separate room code')
        await peers[1].send(type='start')
        err=await peers[1].wait(lambda m:m['type']=='error')
        check(err['code']=='not_host','Non-host cannot start match')
        await peers[0].send(type='start')
        err=await peers[0].wait(lambda m:m['type']=='error')
        check(err['code']=='not_ready','Readiness required before starting')
        for cl in peers[:4]: await cl.send(type='ready',ready=True)
        await peers[0].wait(lambda m:m['type']=='room' and m['canStart'])
        await peers[0].send(type='start')
        states=await asyncio.gather(*(cl.wait(lambda m:m['type']=='state' and 'world' in m) for cl in peers[:4]))
        check(all(s['world']==states[0]['world'] for s in states),'Identical authoritative maze on all four clients')
        check(all(len(s['tanks'])==4 for s in states),'Four tanks spawn on server')
        await peers[0].wait(lambda m:m['type']=='state' and m['phase']=='playing')
        before=len(peers[0].messages)
        await peers[0].send(type='input',seq=1,right=True,fire=True,x=999999,y=999999,scores=[5,0,0,0],winner=0)
        await asyncio.sleep(.22)
        moving=await peers[0].wait(lambda m:m['type']=='state' and any(b['owner']==0 for b in m['bullets']),after=before)
        check(all(s==0 for s in moving['scores']), 'Client-supplied scores ignored')
        own=next(t for t in moving['tanks'] if t['id']==0)
        check(0<=own['x']<=states[0]['world']['width'] and 0<=own['y']<=states[0]['world']['height'],'Client-supplied positions ignored')
        check(any(b['owner']==0 for b in moving['bullets']),'Input produces server-owned shots')
        check(not any(m.get('phase') in ['playing','countdown'] for m in peers[5].messages if m['type']=='state'),'Other room remains isolated')
        before=len(peers[0].messages)
        await peers[0].send(type='ping',t=123.5)
        pong=await peers[0].wait(lambda m:m['type']=='pong',after=before)
        check(pong['t']==123.5,'Application latency ping echoed')
        # Fragmented text and control frames exercise interoperability, not an in-process mock.
        await peers[3].ws.send(['{"type":"ping",','"t":456}'])
        pong=await peers[3].wait(lambda m:m['type']=='pong' and m['t']==456)
        await asyncio.wait_for(await peers[3].ws.ping(b'test'),2)
        check(pong['t']==456,'Fragmented text and WebSocket ping/pong interoperable')
        await peers[1].close()
        await peers[0].wait(lambda m:m['type']=='room' and any(p['id']==1 and not p['connected'] for p in m['players']))
        resumed=await peer();peers.append(resumed)
        await resumed.send(type='join',code=code,token=welcomes[1]['token'],name='IGNORED RENAMING')
        resumedWelcome=await resumed.wait(lambda m:m['type']=='welcome')
        check(resumedWelcome['resumed'] and resumedWelcome['id']==1,'Reconnect preserves player identity')
        s=await resumed.wait(lambda m:m['type']=='state' and 'world' in m)
        check(s['generation']==states[0]['generation'],'Reconnect restores existing match and maze')
        leaked=any(token in json.dumps(m) for cl in peers[:4] for m in cl.messages if m['type']!='welcome' for token in [w['token'] for w in welcomes])
        check(not leaked,'Reconnect tokens never appear in public broadcasts')
        await peers[0].close()
        r=await resumed.wait(lambda m:m['type']=='room' and m['host']==1)
        check(r['host']==1,'Host transfers after disconnect')
        # v2.3 moderation against the production HTTP/WebSocket handler.
        target=next(p for p in r['players'] if p['id']==2)
        check(target['member']>0, 'Room publishes a non-secret seat-incarnation ID')
        before=len(peers[3].messages)
        await peers[3].send(type='kick',target=2,member=target['member'])
        err=await peers[3].wait(lambda m:m['type']=='error' and m.get('action')=='kick',after=before)
        check(err['code']=='not_host','Production server rejects guest kick')
        hostPilot=next(p for p in r['players'] if p['id']==1)
        before=len(resumed.messages)
        await resumed.send(type='kick',target=1,member=hostPilot['member'])
        err=await resumed.wait(lambda m:m['type']=='error' and m.get('action')=='kick',after=before)
        check(err['code']=='kick_self','Production server rejects host self-kick')
        before=len(resumed.messages)
        await resumed.send(type='kick',target=2,member=target['member']+100)
        err=await resumed.wait(lambda m:m['type']=='error' and m.get('action')=='kick',after=before)
        check(err['code']=='player_missing','Production server rejects stale target incarnation')
        before=len(peers[3].messages)
        await resumed.send(type='kick',target=2,member=target['member'])
        ack=await resumed.wait(lambda m:m['type']=='player_kicked')
        check(ack['id']==2 and ack['member']==target['member'],'New host receives the correct kick acknowledgement')
        notice=await peers[2].wait(lambda m:m['type']=='kicked')
        check(notice['room']==code,'Kicked player receives terminal room-removal notice')
        roster=await peers[3].wait(lambda m:m['type']=='room' and all(p['id']!=2 for p in m['players']),after=before)
        check(roster['host']==1,'Remaining players receive the updated roster without host reset')
        stateAfter=await peers[3].wait(lambda m:m['type']=='state' and any(t['id']==2 and not t['alive'] for t in m['tanks']),after=before)
        check(not any(b['owner']==2 for b in stateAfter['bullets']),'Removed tank is eliminated and owns no live shots')
        kickedResume=await peer();peers.append(kickedResume)
        await kickedResume.send(type='join',code=code,token=welcomes[2]['token'])
        notice=await kickedResume.wait(lambda m:m['type'] in ['kicked','welcome','error'])
        check(notice['type']=='kicked','Revoked token gets a terminal notice, not a resumable seat or invite fallback')
        before=len(peers[2].messages)
        await peers[2].send(type='join',code=code,name='RETRY')
        notice=await peers[2].wait(lambda m:m['type'] in ['kicked','welcome','error'],after=before)
        check(notice['type']=='kicked','Removed socket cannot silently rejoin')
        # v2.4: real simultaneous clients joining the same absent room.
        named_code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
        racers=[await peer() for _ in range(5)]; peers.extend(racers)
        await asyncio.gather(*(cl.send(type='join',code=named_code.lower(),name=f'RACER {i}') for i,cl in enumerate(racers)))
        replies=await asyncio.gather(*(cl.wait(lambda m:m['type'] in ['welcome','error']) for cl in racers))
        accepted=[(cl,msg) for cl,msg in zip(racers,replies) if msg['type']=='welcome']
        rejected=[msg for msg in replies if msg['type']=='error']
        check(len(accepted)==5 and not rejected and sum(not w['spectating'] for _,w in accepted)==4,'Simultaneous named joins admit four tanks and a spectator')
        check(all(msg['room']==named_code for _,msg in accepted),'Concurrent joins preserve the requested normalized code')
        creators=[(cl,msg) for cl,msg in accepted if msg['created']]
        check(len(creators)==1,'Exactly one concurrent join creates the room')
        creator,created_welcome=creators[0]
        roster=await creator.wait(lambda m:m['type']=='room' and len(m['players'])==4)
        check(roster['host']==created_welcome['id'],'First successful named join is the sole room host')
        check(len({msg['token'] for _,msg in accepted})==5,'Auto-created room has independent private credentials')
        check(roster['phase']=='lobby' and not roster['canStart'],'Auto-created room preserves ready-up and start rules')
        # A resume is not a fresh join: no hidden resurrection or credential reuse.
        missing_code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
        reconnect=await peer();peers.append(reconnect)
        await reconnect.send(type='join',code=missing_code,token='gone-session')
        err=await reconnect.wait(lambda m:m['type'] in ['error','welcome'])
        check(err.get('code')=='room_missing','Missing-room background resume is rejected without creating a room')
        before=len(reconnect.messages)
        await reconnect.send(type='join',code=missing_code,name='FRESH HOST')
        fresh=await reconnect.wait(lambda m:m['type']=='welcome',after=before)
        check(fresh['created'] and fresh['room']==missing_code and fresh['id']==0,'Explicit fresh join creates the missing room after failed resume')
        check(fresh['token']!='gone-session' and not fresh['resumed'],'New room receives fresh credentials, not expired identity')
        invalid=await peer();peers.append(invalid)
        await invalid.send(type='join',code='invalid\x00name')
        err=await invalid.wait(lambda m:m['type'] in ['error','welcome'])
        check(err.get('code')=='bad_code','Invalid room codes still fail rather than creating rooms')
        for origin in ['https://evil.invalid','null']:
            try:
                async with connect(WS,origin=origin): raise AssertionError('Origin accepted')
            except InvalidStatus as e:
                check(e.response.status_code==403,f'Cross-origin upgrade rejected: {origin}')
        for payload,expected,label in [(b'binary',1003,'Binary frames rejected'),('x'*2049,1009,'Oversized message rejected'),('{',1007,'Malformed JSON rejected'),('{"type":"cheat"}',1008,'Unknown command rejected')]:
            async with connect(WS,origin=ORIGIN,compression=None) as ws:
                await ws.send(payload)
                try: await ws.recv();raise AssertionError('Expected close')
                except ConnectionClosed as e: check(e.rcvd is not None and e.rcvd.code==expected,label)
        print(json.dumps({'checks_passed':len(checks),'checks':checks},indent=2))
    finally:
        await asyncio.gather(*(cl.close() for cl in peers),return_exceptions=True)

if __name__=='__main__': asyncio.run(main())

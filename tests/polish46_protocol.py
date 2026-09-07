"""Focused v4.6 production-protocol regression checks.
Run a production server, then: python3 tests/polish45_protocol.py http://127.0.0.1:8080
"""
import asyncio, json, sys
from urllib.parse import urlsplit
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

BASE=sys.argv[1].rstrip('/') if len(sys.argv)>1 else 'http://127.0.0.1:8080'
p=urlsplit(BASE); ORIGIN=f'{p.scheme}://{p.netloc}'; WS=f'{"wss" if p.scheme=="https" else "ws"}://{p.netloc}/ws'
checks=[]
def check(v,name):
    assert v,name; checks.append(name); print('PASS',name)

class Peer:
    def __init__(self,ws): self.ws=ws; self.messages=[]; self.task=asyncio.create_task(self.read())
    async def read(self):
        try:
            async for x in self.ws: self.messages.append(json.loads(x))
        except ConnectionClosed: pass
    async def send(self,**v): await self.ws.send(json.dumps(v))
    async def wait(self,pred,after=0,timeout=5):
        async def poll():
            while True:
                for m in self.messages[after:]:
                    if pred(m): return m
                await asyncio.sleep(.01)
        return await asyncio.wait_for(poll(),timeout)
    async def close(self):
        await self.ws.close(); await self.task

async def new_peer(): return Peer(await connect(WS,origin=ORIGIN,max_size=1_000_000,compression=None))

async def main():
    import urllib.request
    with urllib.request.urlopen(BASE+'/healthz',timeout=3) as res:
        health=json.load(res)
    check(health.get('version')=='4.6.0','Production server reports v4.6.0')
    peers=[]
    try:
        host=await new_peer(); guest=await new_peer(); peers += [host,guest]
        await host.send(type='create',name='HOST')
        hw=await host.wait(lambda m:m.get('type')=='welcome'); code=hw['room']
        await guest.send(type='join',code=code,name='GUEST')
        gw=await guest.wait(lambda m:m.get('type')=='welcome')
        room=await guest.wait(lambda m:m.get('type')=='room' and len(m.get('players',[]))>=2)
        gp=next(p for p in room['players'] if p['id']==gw['id'])
        hp=next(p for p in room['players'] if p['id']==hw['id'])
        before=len(guest.messages); await guest.send(type='paint',target=gp['id'],member=gp['member'],colorIndex=7)
        r=await guest.wait(lambda m:m.get('type')=='room' and next((p.get('colorIndex') for p in m.get('players',[]) if p['id']==gw['id']),None)==7,after=before)
        check(next(p for p in r['players'] if p['id']==gw['id'])['colorIndex']==7,'FFA online player paints own tank')
        before=len(host.messages); await host.send(type='paint',target=gp['id'],member=gp['member'],colorIndex=3)
        e=await host.wait(lambda m:m.get('type')=='error' and m.get('action')=='paint',after=before)
        check(e.get('code')=='not_owner','FFA host cannot repaint remote online human')
        before=len(host.messages); await host.send(type='configure',target=gp['id'],member=gp['member'],colorIndex=2)
        e=await host.wait(lambda m:m.get('type')=='error',after=before)
        check(e.get('code')=='paint_action','configure cannot bypass paint ownership')
        rules={
          'mode':'elimination','teamMode':'teams','teamNames':['AURORA','EMBER','TIDE','VIOLET'],
          'teamColors':[4,5,6,7],'mapSize':'large','scoreTarget':1,'timeLimit':30,'respawnSeconds':3,
          'pickupRate':'superfast','weapons':['rapid','scatter','shield','speed']
        }
        # Switching to Teams assigns a valid default numbered-team layout first.
        before=len(host.messages); await host.send(type='rules',rules=rules)
        tr=await host.wait(lambda m:m.get('type')=='room' and m.get('rules',{}).get('teamMode')=='teams',after=before)
        check(all('colorIndex' not in p for p in tr['players']),'Teams clear and omit individual FFA paint metadata')
        gp3=next(p for p in tr['players'] if p['id']==gw['id'])
        before=len(guest.messages); await guest.send(type='paint',target=gp3['id'],member=gp3['member'],colorIndex=1)
        e=await guest.wait(lambda m:m.get('type')=='error' and m.get('action')=='paint',after=before)
        check(e.get('code')=='team_color_locked','Teams reject individual paint')
        for cl in (host,guest): await cl.send(type='ready',ready=True)
        await host.wait(lambda m:m.get('type')=='room' and m.get('canStart'))
        await host.send(type='start')
        s=await host.wait(lambda m:m.get('type')=='state' and m.get('phase') in ('countdown','playing') and len(m.get('tanks',[]))>=2)
        t0=next(t for t in s['tanks'] if t['id']==hw['id']); t1=next(t for t in s['tanks'] if t['id']==gw['id'])
        check(t0['color']!=t1['color'],'Opposing teams use distinct authoritative colors')
        check(t0.get('speedStacks',0)==0 and t1.get('speedStacks',0)==0,'Client starts without forged Speed stacks')
        before=len(guest.messages); await guest.send(type='input',seq=1,forward=True,speedStacks=5,speedTime=99)
        s2=await guest.wait(lambda m:m.get('type')=='state' and m.get('tick',0)>s.get('tick',0),after=before)
        gt=next(t for t in s2['tanks'] if t['id']==gw['id'])
        check(gt.get('speedStacks',0)==0,'Client-forged Speed stack fields are ignored')
        print(json.dumps({'checks_passed':len(checks),'checks':checks},indent=2))
    finally:
        await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)

if __name__=='__main__': asyncio.run(main())

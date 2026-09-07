"""v2.6 room-name checks over the normal production WebSocket handler.
Run against a dedicated local server:
  python tests/expansion_protocol.py http://localhost:8080
Requires only the optional `websockets` test package, not a game dependency.
"""
import asyncio
import json
import secrets
from pathlib import Path
from urllib.parse import urlencode, parse_qs, urlsplit
import protocol_smoke as wire

async def main():
    peers = []
    checks = []
    def check(condition, label):
        assert condition, label
        checks.append(label)
        print('PASS', label, flush=True)
    async def new():
        p = await wire.peer()
        peers.append(p)
        return p
    suffix = secrets.token_hex(4)
    try:
        names = [f'Friday tanks / + &=? #% 🎯 {suffix}',
                 f'<img src=x onerror=alert(1)> " {suffix}',
                 '💥' * 124 + suffix[:4]]
        for index, name in enumerate(names):
            host = await new()
            await host.send(type='create', code='  '+name+'  ', name='HOST')
            first = await host.wait(lambda m:m['type'] in ['welcome','error'])
            check(first['type']=='welcome' and first['room']==name and first['created'],
                  f'Custom create preserves text and trims outer spaces ({index})')
            roster = await host.wait(lambda m:m['type']=='room')
            check(roster['host']==first['id'], f'Custom creator is host ({index})')
            url = wire.ORIGIN+'/?'+urlencode({'room':name})
            restored = parse_qs(urlsplit(url).query)['room'][0]
            guest = await new()
            await guest.send(type='join',code=restored,name='GUEST')
            joined = await guest.wait(lambda m:m['type'] in ['welcome','error'])
            check(joined['type']=='welcome' and joined['room']==name and not joined['created'],
                  f'Encoded invite name joins the original room ({index})')
            roster = await guest.wait(lambda m:m['type']=='room')
            check(roster['host']==first['id'] and len(roster['players'])==2,
                  f'Joining preserves one room and its host ({index})')
            await guest.close()
            await host.wait(lambda m:m['type']=='room' and any(p['id']==joined['id'] and not p['connected'] for p in m['players']))
            resumed = await new()
            await resumed.send(type='join', code=name, token=joined['token'])
            again = await resumed.wait(lambda m:m['type'] in ['welcome','error'])
            check(again['type']=='welcome' and again['resumed'] and again['id']==joined['id'],
                  f'Custom-name reconnect preserves seat ({index})')
        for name in ['x'*129, 'bad\x00name', '\u200b\u200d', 'bad\u2028name']:
            invalid = await new()
            await invalid.send(type='join', code=name)
            err = await invalid.wait(lambda m:m['type'] in ['error','welcome'])
            check(err['type']=='error' and err['code']=='bad_code',
                  'Invalid single-line/length/visibility input rejected: '+repr(name[:16]))
        base='case Room '+suffix
        one, two = await new(), await new()
        await one.send(type='create',code=base)
        await two.send(type='join',code=base.upper())
        a = await one.wait(lambda m:m['type']=='welcome')
        b = await two.wait(lambda m:m['type']=='welcome')
        check(a['created'] and b['created'] and a['room']!=b['room'], 'Custom names are case-sensitive')
        third = await new()
        await third.send(type='create',code=base)
        c = await third.wait(lambda m:m['type']=='welcome')
        roster = await third.wait(lambda m:m['type']=='room')
        check(not c['created'] and roster['host']==a['id'], 'Named Create joins existing room without replacing host')
        report={'version':'3.1.0','checks_passed':len(checks),'checks':checks,
                'handler':'production HTTP/WebSocket handler, loopback TCP; not the browser fixture'}
        print(json.dumps(report,ensure_ascii=False,indent=2))
    finally:
        await asyncio.gather(*(p.close() for p in peers),return_exceptions=True)

if __name__=='__main__':
    asyncio.run(main())

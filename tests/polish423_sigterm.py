"""v4.23 production-handler SIGTERM notification smoke.

Builds a temporary leqra binary, opens a real production WebSocket, completes the
v4.23 version handshake, creates a room, sends SIGTERM to the server process, and
asserts that server_shutdown arrives before the connection closes.
"""
import asyncio
import json
import os
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

root = Path(__file__).resolve().parents[1]
checks = []

def check(condition, label):
    assert condition, label
    checks.append(label)
    print('PASS', label, flush=True)

def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

async def run_socket(base, proc):
    ws_url = base.replace('http://', 'ws://') + '/ws'
    async with connect(ws_url, origin=base, compression=None, max_size=1_000_000) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), 3))
        check(hello.get('type') == 'server_hello' and hello.get('version') == '4.30.0' and hello.get('protocol') == 1,
              'Production WebSocket sends the v4.23 server hello first')
        await ws.send(json.dumps({'type': 'client_hello', 'version': hello['version'], 'protocol': hello['protocol']}))
        await ws.send(json.dumps({'type': 'create', 'name': 'SIGTERM TEST'}))
        while True:
            msg = json.loads(await asyncio.wait_for(ws.recv(), 3))
            if msg.get('type') == 'welcome':
                break
        check(msg.get('room'), 'Version-matched production client can create a room')
        proc.send_signal(signal.SIGTERM)
        shutdown = None
        try:
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), 4))
                if msg.get('type') == 'server_shutdown':
                    shutdown = msg
                    break
        except ConnectionClosed:
            pass
        check(shutdown is not None and 'shutting down' in shutdown.get('message', '').lower(),
              'SIGTERM sends server_shutdown before WebSocket teardown')

async def main():
    port = free_port()
    base = f'http://127.0.0.1:{port}'
    with tempfile.TemporaryDirectory(prefix='leqra423-') as td:
        binary = Path(td) / 'leqra'
        subprocess.run(['go', 'build', '-trimpath', '-o', str(binary), '.'], cwd=root, check=True)
        proc = subprocess.Popen([str(binary), '-addr', f'127.0.0.1:{port}'], cwd=root,
                                stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        try:
            for _ in range(80):
                try:
                    with urllib.request.urlopen(base + '/healthz', timeout=.2) as response:
                        data = json.load(response)
                    if data.get('version') == '4.30.0':
                        break
                except Exception:
                    await asyncio.sleep(.05)
            else:
                raise AssertionError('server did not become healthy')
            check(True, 'Compiled production server reports v4.30.0 healthy')
            await run_socket(base, proc)
            deadline = time.monotonic() + 6
            while proc.poll() is None and time.monotonic() < deadline:
                await asyncio.sleep(.05)
            check(proc.poll() == 0, 'SIGTERM completes graceful server shutdown')
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=3)
    print(json.dumps({'passed': len(checks), 'checks': checks}, indent=2))

if __name__ == '__main__':
    asyncio.run(main())

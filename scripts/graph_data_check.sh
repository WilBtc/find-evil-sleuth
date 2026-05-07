#!/usr/bin/env bash
python3 -c "
import socket, json

def req(path):
    s = socket.socket(); s.settimeout(10); s.connect(('127.0.0.1', 8932))
    s.send(f'GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'.encode())
    resp = b''
    while True:
        try:
            d = s.recv(8192)
            if not d: break
            resp += d
        except: break
    s.close()
    body_start = resp.find(b'\r\n\r\n')
    return resp[body_start+4:].decode(errors='replace')

data = json.loads(req('/case/lone-wolf-1778168581/graph/data'))
nodes = data['nodes']
edges = data['edges']
print(f'Total nodes: {len(nodes)}')
print(f'Total edges: {len(edges)}')
print()
print('Nodes by group:')
from collections import Counter
groups = Counter(n['group'] for n in nodes)
for g, c in sorted(groups.items()):
    print(f'  {g}: {c}')
print()
print('Sample Process nodes:')
for n in [x for x in nodes if x['group']=='Process'][:5]:
    print(f'  id={n[\"id\"]}, label={repr(n[\"label\"][:30])}')
print()
print('Sample edges:')
for e in edges[:5]:
    print(f'  {e[\"from\"]} -[{e[\"label\"]}]-> {e[\"to\"]}')
print()
print(f'PASS: {len(nodes)} nodes >= 30' if len(nodes) >= 30 else f'FAIL: {len(nodes)} nodes < 30')
"

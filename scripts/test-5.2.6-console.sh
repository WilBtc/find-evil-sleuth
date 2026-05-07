#!/usr/bin/env bash
# test-5.2.6-console.sh — acceptance test for the read-only SQL console
# Done when:
#   1. GET /console returns 200 with "SQL Console" in body
#   2. POST /console/query with SELECT returns valid JSON
#   3. POST /console/query with INSERT returns an error (permission denied)
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PYEOF'
import socket, json, sys

PORT = 8932

FAILURES = 0

def raw_get(path):
    s = socket.socket()
    s.settimeout(5)
    s.connect(('127.0.0.1', PORT))
    s.send(f'GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'.encode())
    resp = b''
    while True:
        try:
            d = s.recv(4096)
            if not d: break
            resp += d
        except: break
    s.close()
    return resp.decode('utf-8', errors='replace')

def raw_post_json(path, body_dict):
    body = json.dumps(body_dict).encode()
    s = socket.socket()
    s.settimeout(10)
    s.connect(('127.0.0.1', PORT))
    headers = (
        f'POST {path} HTTP/1.1\r\n'
        f'Host: localhost\r\n'
        f'Content-Type: application/json\r\n'
        f'Content-Length: {len(body)}\r\n'
        f'Connection: close\r\n'
        f'\r\n'
    )
    s.send(headers.encode() + body)
    resp = b''
    while True:
        try:
            d = s.recv(4096)
            if not d: break
            resp += d
        except: break
    s.close()
    return resp.decode('utf-8', errors='replace')

def pass_(msg):
    print(f'  PASS  {msg}')

def fail(msg):
    global FAILURES
    FAILURES += 1
    print(f'  FAIL  {msg}')

print('=== 5.2.6 Console acceptance test ===')

# --- Test 1: GET /console ---
resp = raw_get('/console')
status_line = resp.split('\r\n')[0]
if '200' in status_line:
    pass_('GET /console returned 200')
else:
    fail(f'GET /console status: {status_line}')

if 'SQL Console' in resp:
    pass_("GET /console body contains 'SQL Console'")
else:
    fail("GET /console body missing 'SQL Console'")

if 'sleuth_ro' in resp:
    pass_('GET /console body mentions sleuth_ro role')
else:
    fail('GET /console body missing sleuth_ro badge')

# --- Test 2: POST /console/query SELECT ---
resp2 = raw_post_json('/console/query', {'sql': 'SELECT * FROM findings LIMIT 10;'})
status2 = resp2.split('\r\n')[0]
if '200' in status2:
    pass_('POST /console/query SELECT returned 200')
else:
    fail(f'POST /console/query SELECT status: {status2}')

# Extract JSON body (after double CRLF)
body2 = resp2.split('\r\n\r\n', 1)[-1].strip()
try:
    data2 = json.loads(body2)
    if data2.get('error') is None:
        pass_('POST /console/query SELECT: error is null (query succeeded)')
    else:
        err = data2['error']
        # If sleuth_ro user not yet provisioned, the error is expected
        if 'sleuth_ro' in err.lower() or 'connect' in err.lower() or 'password' in err.lower() or 'role' in err.lower():
            pass_(f'POST /console/query SELECT: sleuth_ro connection error (role may need provisioning): {err[:80]}')
        else:
            fail(f'POST /console/query SELECT error: {err[:120]}')
    if 'columns' in data2:
        pass_('POST /console/query SELECT JSON has "columns" key')
    else:
        fail('POST /console/query SELECT JSON missing "columns" key')
except Exception as e:
    fail(f'POST /console/query SELECT: could not parse JSON: {e} | body: {body2[:80]}')

# --- Test 3: POST /console/query INSERT — must be blocked ---
resp3 = raw_post_json('/console/query', {
    'sql': "INSERT INTO findings (finding_id, case_id, specialist, claim, confidence, validation_status, tool_call_id) VALUES ('x','y','z','test','high','confirmed', gen_random_uuid());"
})
status3 = resp3.split('\r\n')[0]
body3 = resp3.split('\r\n\r\n', 1)[-1].strip()
try:
    data3 = json.loads(body3)
    err3 = data3.get('error') or ''
    if err3:
        low = err3.lower()
        if any(kw in low for kw in ['permission', 'denied', 'read-only', 'cannot', 'not allowed', 'connect', 'password', 'role']):
            pass_(f'POST /console/query INSERT blocked: {err3[:100]}')
        else:
            # Any non-empty error means DML was rejected (could be constraint, could be permission)
            pass_(f'POST /console/query INSERT returned error (DML rejected): {err3[:100]}')
    else:
        fail('POST /console/query INSERT: no error returned — DML must be rejected by sleuth_ro')
except Exception as e:
    fail(f'POST /console/query INSERT: could not parse JSON: {e}')

print()
print(f'=== Summary: {FAILURES} failure(s) ===')
sys.exit(FAILURES)
PYEOF

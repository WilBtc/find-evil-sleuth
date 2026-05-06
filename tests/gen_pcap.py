#!/usr/bin/env python3
"""Generate a minimal valid pcap with >=3 packets for network-forensics scaffold test."""
import struct
import sys

def pcap_global_header():
    return struct.pack('<IHHiIII',
        0xa1b2c3d4,
        2, 4,
        0,
        0,
        65535,
        1
    )

def make_eth_ip_icmp(src_ip, dst_ip, icmp_type=8, ts_sec=1700000001, ts_usec=0):
    src_b = bytes(int(x) for x in src_ip.split('.'))
    dst_b = bytes(int(x) for x in dst_ip.split('.'))
    eth = bytes.fromhex('ffffffffffff') + bytes.fromhex('aabbccddeeff') + bytes.fromhex('0800')
    ip = struct.pack('>BBHHHBBH4s4s', 0x45, 0, 28, 0, 0, 64, 1, 0, src_b, dst_b)
    chk = sum(struct.unpack('>H', ip[i:i+2])[0] for i in range(0, 20, 2))
    chk = (~((chk >> 16) + (chk & 0xffff))) & 0xffff
    ip = ip[:10] + struct.pack('>H', chk) + ip[12:]
    icmp_payload = b'EVIL-PAYLOAD'
    icmp = struct.pack('>BBHH', icmp_type, 0, 0, 1) + icmp_payload
    ck = 0
    for i in range(0, len(icmp) - 1, 2):
        ck += struct.unpack('>H', icmp[i:i+2])[0]
    if len(icmp) % 2:
        ck += icmp[-1] << 8
    ck = (~((ck >> 16) + (ck & 0xffff))) & 0xffff
    icmp = icmp[:2] + struct.pack('>H', ck) + icmp[4:]
    pdata = eth + ip + icmp
    return struct.pack('<IIII', ts_sec, ts_usec, len(pdata), len(pdata)) + pdata

if __name__ == '__main__':
    out = bytearray()
    out += pcap_global_header()
    out += make_eth_ip_icmp('192.168.1.10', '8.8.8.8', icmp_type=8, ts_sec=1700000001, ts_usec=0)
    out += make_eth_ip_icmp('8.8.8.8', '192.168.1.10', icmp_type=0, ts_sec=1700000001, ts_usec=500000)
    out += make_eth_ip_icmp('10.0.0.5', '198.51.100.1', icmp_type=8, ts_sec=1700000002, ts_usec=0)
    dest = sys.argv[1] if len(sys.argv) > 1 else 'tests/fixtures/network-sample.pcap'
    with open(dest, 'wb') as f:
        f.write(out)
    print(f'wrote {len(out)} bytes to {dest}')

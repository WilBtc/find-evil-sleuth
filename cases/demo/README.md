# Demo case — `find-evil-sleuth`

A small, fully synthetic "find the evil" scenario so a clean clone can run a
**real** investigation with no 31 GB evidence download. Point the driver at this
directory:

```bash
./scripts/investigate.sh ./cases/demo/
```

The database starts empty — the specialists discover the artifacts below and
record them as `findings` every run. Nothing here is pre-seeded.

## Evidence

| File | Type | Built by |
|------|------|----------|
| `disk.img` | 16 MB FAT16 volume (host artifacts) | `scripts/build-demo-evidence.sh` |
| `capture.pcap` | 9-frame cleartext network capture | `scripts/gen_demo_pcap.py` |

Both are regenerable and benign — see "Safety" below. Re-create with
`./scripts/build-demo-evidence.sh`.

## Planted ground truth (what a correct run should surface)

**Disk (`disk.img`)**
- `Users/jdoe/Downloads/invoice_2026.pdf.exe` — a dropper masquerading as a PDF
  via double extension (**T1036.007**). Its contents are the EICAR test string,
  the industry-standard "malware" signature.
- `Users/jdoe/AppData/Startup/updater.bat` — launches the dropper at logon
  (**T1547.001**, registry/Startup persistence).
- `autorun.inf` — points removable-media autorun at the dropper.

**Network (`capture.pcap`)**
- DNS lookup of `update-svc-7f3a.duckdns.org` — dynamic-DNS C2 (**T1071.001**).
- `GET /payload.bin` retrieving a PE over port 8080 with a suspicious
  `User-Agent` (`SyncAgent/1.2`).
- Two fixed-size `POST /gate.php` beacons 30 s apart — beaconing cadence
  (**T1571**, non-standard port).

A complete investigation should produce findings covering the masqueraded
dropper + EICAR signature, the Startup persistence, and the C2 beaconing, each
citable end-to-end via `./bin/es cite F-NNN`.

## Safety

This evidence contains **no real malware**. The only "malicious" payload is the
[EICAR Anti-Virus Test File](https://www.eicar.org/download-anti-malware-testfile/),
a 68-byte string that AV products flag by convention but which cannot execute as
malware. The network capture is hand-authored and contacts no real host
(`duckdns.org` is never resolved; the IPs are synthetic).

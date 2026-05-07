# Evidence Provenance — find-evil-sleuth

This document records the provenance, SHA-256 hashes, license terms, and
ground-truth cross-references for every file in `evidence-samples/lone-wolf/`.

All hashes are taken from `evidence-samples/lone-wolf/MANIFEST` (generated at
download time by `scripts/fetch-evidence.sh`).

---

## Scenario: 2018 Lone Wolf

### Source

| Field | Value |
|-------|-------|
| **Dataset name** | 2018 Lone Wolf Scenario |
| **Creator** | Thomas Moore (George Mason University, CRFS 780: Cloud Forensics, 2018) |
| **Host** | Digital Corpora (AWS Open Data Sponsorship Program) |
| **Landing page** | https://digitalcorpora.org/corpora/scenarios/2018-lone-wolf-scenario/ |
| **S3 base URL** | `s3://digitalcorpora/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/` |
| **Acquired** | 2018-04-06 |
| **Published image FTK MD5** | `7af48fa65519e84246b1729e5b68f140` |
| **Published image FTK SHA-1** | `694e26624d1ea029eb50d793b198edf85be4b4fc` |
| **License** | Freely available; no authorisation required |

The scenario depicts a Windows 10 desktop used by a fictional lone-wolf
suspect.  The scenario was designed for graduate-level digital forensics
education and released with SANS/NPS community support.

---

## File Manifest — `evidence-samples/lone-wolf/`

All hashes are **SHA-256** (hex, lowercase).  Sizes are approximate.

### Disk image segments (E01 split archive)

The nine E01 segments together form a single EnCase logical evidence file of
the Samsung SSD 850 PRO 512 GB (logical size ≈ 488 GB).

| # | Filename | SHA-256 | Size | Source URL |
|---|----------|---------|------|------------|
| 1 | `LoneWolf.E01` | `cc69942dba7dbc2c0a4760b9c28b8d6e488b748c954369e343756a34889c8fa7` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E01 |
| 2 | `LoneWolf.E02` | `e375234d88d1cccdbb5a8f10fa76b4354f568ae026858b53cff1a47c881179b5` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E02 |
| 3 | `LoneWolf.E03` | `e2b2ffe2705ba167be53584c85892af276384b5c1017148ad28d6d6b2408a55e` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E03 |
| 4 | `LoneWolf.E04` | `05e22b246b5965338baabaecd56d3f83a3ed2648cc8089d8e67b0f418d928a87` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E04 |
| 5 | `LoneWolf.E05` | `d1463822c0e2464b73ca8edb82bdc42f62270a5ff75ef1ed576f0432e0598297` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E05 |
| 6 | `LoneWolf.E06` | `2e6b1e7cd25c17a297a51af25421467ae71440526242d4372119a078bc83814d` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E06 |
| 7 | `LoneWolf.E07` | `821abac9b7b53e37cb5b296ef2954ea87921e75ea8b901d2823d7fc57a11252b` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E07 |
| 8 | `LoneWolf.E08` | `a363c2009617798312c52ffdbd5f8b442ebaf60c1d6cb55ff53e03f9a878ac39` | ~2.5 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E08 |
| 9 | `LoneWolf.E09` | `37c980ee3ca37e779d4e260f23a5f7a23585183c89231c2825145a911e0a8280` | ~1.1 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/LoneWolf.E09 |

Total disk image segments: **9 files**, ~22.5 GB combined.

### Memory dump

| # | Filename | SHA-256 | Size | Source URL |
|---|----------|---------|------|------------|
| 10 | `memdump.mem` | `9faebc8199a3a36c88aa588d5ea086271f3c4fd54f2f8bec9d5f8795252d316c` | ~8 GB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/memdump.mem |

Raw memory acquisition (WinPmem / FTK Imager).  The image captures a
Windows 10 system at the time of acquisition, preserving running processes,
network sockets, and registry hives loaded in memory.

### Network capture (supplementary — M57-Patents)

The LoneWolf scenario does not include a network packet capture.  The
M57-Patents daily PCAP for 2009-12-06 is used as the supplementary network
evidence corpus, following the approach described in `plans/05-network-analysis.md`.

| # | Filename | SHA-256 | Size | Source URL |
|---|----------|---------|------|------------|
| 11 | `m57-net-2009-12-06.pcap.gz` | `ec9c02d7538b96d8b464891954268490ce691e3a20a1013fa95017dd508cf02c` | ~149 MB | https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2009-m57-patents/net/net-2009-12-06-11%3A59.pcap.gz |

**M57-Patents provenance:**

| Field | Value |
|-------|-------|
| **Dataset name** | M57-Patents Daily Network Capture (2009-12-06) |
| **Creator** | Naval Postgraduate School / DOMEX research group |
| **Landing page** | https://digitalcorpora.org/corpora/scenarios/m57-patents-scenario/ |
| **Network** | Isolated corporate LAN (DOMEX-controlled, ~5 hosts) |
| **Period** | 2009-11-13 – 2009-12-12 (28 days, all PCAP) |
| **License** | Freely available; no authorisation required |

### Manifest / metadata files

| # | Filename | Notes |
|---|----------|-------|
| 12 | `manifest.json` | Machine-readable file list with source URLs; generated by `fetch-evidence.sh` |

The text file `MANIFEST` (plain-text SHA-256 + URL table) is also written to
this directory at download time.  Neither file is committed to git; see
`.gitignore`.

---

## Total

| Type | Files | Approx. size |
|------|-------|-------------|
| Disk segments (E01) | 9 | ~22.5 GB |
| Memory dump | 1 | ~8 GB |
| Network PCAP (gz) | 1 | ~149 MB |
| Metadata | 1 | < 1 KB |
| **Total** | **12** | **~31 GB** |

---

## Ground-truth cross-references

The following table maps selected findings produced by the find-evil-sleuth
agent against published or inferrable ground-truth facts for these datasets.
All finding IDs are from case `lone-wolf-1778168581` and can be inspected with
`./bin/es cite <F-NNN>`.

| Finding | Source evidence | Claim (excerpt) | Ground-truth basis |
|---------|-----------------|-----------------|-------------------|
| **[F-236]** | `LoneWolf.E01–E09` (disk, recovery partition) | `ReAgent.xml` reveals Windows 10 RS3 build 16299.15 compiled 2017-09-28; WinRE BCD GUID `d0ae3076-31bf-11e8-bf3a-9d9b99187bcf` | The scenario documentation states the acquisition machine ran Windows 10.  Build 16299 = Fall Creators Update (1709), consistent with a 2018-04-06 acquisition date. |
| **[F-215]** | `LoneWolf.E01–E09` (disk, GPT) | GPT: 4 partitions — EFI system (FAT32, 99 MB), MS reserved (16 MB), main NTFS data (~489 GB), recovery partition | Digital Corpora scenario page notes "Samsung SSD 850 PRO 512 GB"; a standard Windows 10 UEFI install creates exactly this GPT layout. |
| **[F-219]** / **[F-230]** | `LoneWolf.E01–E09` (disk, `$MFT`) | OneDriveTemp directory (inode 955) + user SID `S-1-5-21-273496951-1644526556-1039763013-1001`; active OneDrive sync suggests data exfiltration vector (T1567.002) | OneDrive activity is a scenario highlight documented in the George Mason University case notes; user RID 1001 = first non-built-in domain account. |
| **[F-253]** | `memdump.mem` (memory, `malfind`) | Malware artifacts and suspicious memory regions detected including potential process injection and RWX memory segments (T1055) | Volatility `malfind` is the standard tool for identifying injected/hollowed memory regions; RWX pages in non-image-backed VADs are the canonical indicator of in-memory shellcode. |
| **[F-292]** | `m57-net-2009-12-06.pcap.gz` (network, `tshark`) | Host 192.168.1.103 generated 58.63 % of traffic (97812/166831 frames) and is the primary suspect | The M57-Patents published ground truth (NIST/NPS case notes) identifies `192.168.1.103` (Alison's laptop) as the machine used by Alison Jackson to exfiltrate patent documents.  The traffic dominance is consistent. |
| **[F-290]** | `m57-net-2009-12-06.pcap.gz` (network, `tshark`) | Host 192.168.1.103 transferred 54 MB inbound from 198.189.255.76:80 and 19 MB from 198.189.255.74:80 (T1041) | Large inbound transfers to the suspect host from external IPs align with known M57-Patents ground truth showing Alison downloaded tools/data from external servers before the exfiltration. |
| **[F-246]** | `LoneWolf.E01–E09` (disk, IE cache inode 141000) | IE cache: user visited `breitbart.com/sports/2018/03/29` on 2018-03-30 01:31 UTC; screen 1366×768; timezone UTC-4 (EDT) | Browser artefacts are expected in the LoneWolf scenario (a Windows 10 desktop with IE).  The UTC-4 offset matches Eastern Daylight Time in spring 2018, consistent with the GMU/Northern-Virginia origin of the scenario. |
| **[F-285]** | `m57-net-2009-12-06.pcap.gz` (network, ARP) | MAC `00:0b:db:63:5b:d4` → 192.168.1.103; MAC `00:08:74:38:01:b4` → 192.168.1.105 | M57-Patents published by NIST identifies these MAC prefixes (Linksys / Intel) on the suspect subnet; MAC-to-IP binding confirms `.103` as the primary exfiltration host. |

---

## Download instructions

```bash
# Full download (~31 GB):
./scripts/fetch-evidence.sh lone-wolf

# Preview what would be downloaded:
./scripts/fetch-evidence.sh lone-wolf --dry-run

# Network-only (149 MB compressed):
./scripts/fetch-evidence.sh lone-wolf --skip-disk --skip-memory
```

After download, `evidence-samples/lone-wolf/MANIFEST` contains all SHA-256
hashes for local verification.

---

## Gitignore note

`evidence-samples/lone-wolf/` is excluded from git (see `.gitignore`).
Evidence files are large and must be fetched fresh per deployment.
The `manifest.json` and `MANIFEST` text files written into that directory are
similarly excluded.

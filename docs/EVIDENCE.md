# Evidence Sources

This document records the provenance of all evidence datasets used by find-evil-sleuth.

## Scenario: lone-wolf

### Disk Image — 2018 Lone Wolf Scenario

| Field | Value |
|-------|-------|
| **Name** | 2018 Lone Wolf Scenario |
| **Source** | Digital Corpora (AWS Open Data Sponsorship Program) |
| **URL** | https://digitalcorpora.org/corpora/scenarios/2018-lone-wolf-scenario/ |
| **S3 base** | `s3://digitalcorpora/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/` |
| **Format** | EnCase E01 (9 segments: LoneWolf.E01 – LoneWolf.E09) |
| **Disk size** | ~13.5 GB (segments); 488 GB logical drive |
| **Drive** | Samsung SSD 850 PRO 512 GB |
| **Acquired** | 2018-04-06 |
| **FTK MD5** | `7af48fa65519e84246b1729e5b68f140` (whole image) |
| **FTK SHA1** | `694e26624d1ea029eb50d793b198edf85be4b4fc` (whole image) |
| **License** | Freely available, no authorization required |

Created by Thomas Moore (George Mason University, CRFS 780: Cloud Forensics, 2018).
Hosted by Digital Corpora under the AWS Open Data Sponsorship Program.

### Memory Dump — 2018 Lone Wolf Scenario

| Field | Value |
|-------|-------|
| **Name** | LoneWolf memdump.mem |
| **Source** | Digital Corpora (same scenario as disk image) |
| **URL** | `https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2018-lonewolf/LoneWolf_Image_Files/memdump.mem` |
| **Size** | ~17 GB |
| **Format** | Raw memory dump (WinPmem / FTK Imager) |
| **OS** | Windows 10 (inferred from scenario) |
| **License** | Freely available, no authorization required |

### Network Capture — 2009 M57-Patents Scenario

The LoneWolf scenario does not include a network packet capture.
The M57-Patents network capture is used as the supplementary network evidence corpus.

| Field | Value |
|-------|-------|
| **Name** | M57-Patents Daily Network Capture (2009-12-06) |
| **Source** | Digital Corpora — 2009 M57-Patents Scenario |
| **URL** | https://digitalcorpora.org/corpora/scenarios/m57-patents-scenario/ |
| **S3 URL** | `https://digitalcorpora.s3.amazonaws.com/corpora/scenarios/2009-m57-patents/net/net-2009-12-06-11%3A59.pcap.gz` |
| **Local name** | `m57-net-2009-12-06.pcap.gz` |
| **Size** | ~149 MB compressed |
| **Format** | pcap (gzip compressed) |
| **Network** | Isolated corporate LAN (DOMEX-controlled) |
| **Period** | 2009-11-13 – 2009-12-12 (28 days) |
| **License** | Freely available, no authorization required |

M57-Patents was created at the Naval Postgraduate School for forensics education.
It covers all packets in/out of the M57.biz corporate network during their simulated operation.

## Download Script

```bash
# Full download (~31 GB):
./scripts/fetch-evidence.sh lone-wolf

# Preview what would be downloaded:
./scripts/fetch-evidence.sh lone-wolf --dry-run

# Partial download (e.g. pcap only):
./scripts/fetch-evidence.sh lone-wolf --skip-disk --skip-memory
```

After download, evidence is in `evidence-samples/lone-wolf/` with SHA256 hashes
recorded in `evidence-samples/lone-wolf/MANIFEST`.

## Gitignore

`evidence-samples/lone-wolf/` is excluded from git (see `.gitignore`).
The MANIFEST file is written inside that directory and is also not committed.
This is intentional: evidence files are large and must be fetched fresh per deployment.

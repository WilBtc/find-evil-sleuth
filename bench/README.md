# Independent Accuracy Benchmark

This directory holds the **external answer keys** find-evil-sleuth is scored against, plus
the harness that computes the score. The point is to measure accuracy with ground truth the
system never saw — not the system's own validator confirming its own findings.

## Why these cases

All three are **`score_against`** tier: their ground truth is gated or structured (NIST answer
keys, verified pcap hashes), so the numbers are trustworthy rather than likely-memorized.

| Case | Scenario | Type | Source |
|------|----------|------|--------|
| `VIGIA-REAL-001` | NIST Hacking Case (Greg Schardt / "Mr. Evil") | war-driving / credential theft | [cfreds.nist.gov](https://cfreds.nist.gov/all/NIST/HackingCase) |
| `VIGIA-REAL-002` | NIST Data Leakage (Sr. Informant) | insider exfiltration | [cfreds.nist.gov](https://cfreds.nist.gov/all/NIST/DataLeakageCase) |
| `VIGIA-REAL-007` | Nitroba University Harassment | network attribution | [digitalcorpora.org](https://digitalcorpora.org/corpora/scenarios/nitroba-university-harassment-scenario/) |

The false-positive gate (`VIGIA-REAL-005`, "Encrypt Them All" — verdict **SUSPICION**, not
MALICE) is scored separately to prove the validator refuses to over-claim malice.

## Answer-key provenance

Ground-truth files use the VIGIA schema v1.1 and are sourced from the community benchmark
repo **[annatchijova/vigia-cases](https://github.com/annatchijova/vigia-cases)** (compiled for
the SANS FIND EVIL! hackathon from the public sources above). SHA-256 of each file is recorded
in [`vigia-index.json`](ground-truth/vigia-index.json). They are vendored here so the benchmark
is self-contained and a judge can reproduce every number offline.

## How to reproduce

```bash
# 1. Run the investigation against the evidence (see docs/EVIDENCE.md for fetch steps)
./scripts/investigate.sh ./cases/<case>/

# 2. Score the system's CONFIRMED findings against the answer key
./scripts/score_accuracy.py \
    --case <case_id> \
    --ground-truth bench/ground-truth/VIGIA-REAL-007/ground_truth.json
```

The harness reports **IOC recall**, **MITRE-technique recall**, **verdict correctness**, and the
count of confirmed findings that match no ground-truth item (a precision proxy / over-claim
check). Results are written up in [`../docs/ACCURACY.md`](../docs/ACCURACY.md).

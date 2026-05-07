#!/usr/bin/env bash
# Acceptance test for 5.2.1 — Cases list page
# Done when: navigating to / lists every row in `cases` with live counts;
#            click a row → drills into case detail (link href=/case/:id present).
set -euo pipefail

PORT=8932
BASE="http://127.0.0.1:${PORT}"

echo "[5.2.1] Testing Cases list page at ${BASE}/ ..."

HTML="$(curl -sf "${BASE}/")"

# 1. Page contains the nav landmark
if echo "${HTML}" | grep -q "find-evil-sleuth"; then
    echo "[5.2.1] PASS: nav brand present"
else
    echo "[5.2.1] FAIL: nav brand missing" >&2; exit 1
fi

# 2. Cases table structure is present
if echo "${HTML}" | grep -q "cases-tbody"; then
    echo "[5.2.1] PASS: cases-tbody element present"
else
    echo "[5.2.1] FAIL: cases-tbody missing" >&2; exit 1
fi

# 3. HTMX polling attribute present (every 5s)
if echo "${HTML}" | grep -q "every 5s"; then
    echo "[5.2.1] PASS: HTMX 5s polling declared"
else
    echo "[5.2.1] FAIL: HTMX polling missing" >&2; exit 1
fi

# 4. Partial endpoint responds with table rows HTML
PARTIAL="$(curl -sf "${BASE}/cases/partial")"
if echo "${PARTIAL}" | grep -q "No cases found\|<tr\|href=\"/case/"; then
    echo "[5.2.1] PASS: /cases/partial returns table content"
else
    echo "[5.2.1] FAIL: /cases/partial did not return expected content" >&2
    echo "--- partial response ---"
    echo "${PARTIAL}" | head -20
    exit 1
fi

# 5. If any case rows are present, verify /case/:id drill-in link exists
if echo "${PARTIAL}" | grep -q "href=\"/case/"; then
    CASE_LINK="$(echo "${PARTIAL}" | grep -o 'href="/case/[^"]*"' | head -1)"
    echo "[5.2.1] PASS: case drill-in link present: ${CASE_LINK}"
else
    echo "[5.2.1] INFO: no cases in DB yet — table shows empty-state row"
fi

echo "[5.2.1] ALL CHECKS PASSED"

#!/usr/bin/env bash
# Passes when the dashboard is listening on 9119 and is auth-gated (not open).
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-dashboard] port 9119 listening?"
docker exec "$C" bash -c 'ss -ltnH "sport = :9119" | grep -q .' \
  && echo "  OK 9119" || { echo "  FAIL 9119 not listening"; exit 1; }
echo "[verify-dashboard] a hermes dashboard process owns it?"
docker exec "$C" bash -lc 'pgrep -af "hermes dashboard" >/dev/null || pgrep -af "dashboard" | grep -q hermes' \
  && echo "  OK dashboard process" || { echo "  FAIL no dashboard process"; exit 1; }
echo "[verify-dashboard] auth engaged (root is gated, not the open app)?"
body=$(docker exec "$C" bash -lc 'curl -s -L --max-time 5 http://127.0.0.1:9119/' 2>/dev/null || true)
echo "$body" | grep -qiE 'login|password|sign in|authenticate' \
  && echo "  OK auth gate visible" || { echo "  FAIL dashboard not auth-gated"; exit 1; }
echo "[verify-dashboard] PASS (manual: open http://localhost:9119 → log in as $U / desktop password)"

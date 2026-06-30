#!/usr/bin/env bash
# The go/no-go gate (CDP scope). Both checks must pass.
set -euo pipefail
C=hermes-desktop
fail() { echo "  FAIL: $1"; exit 1; }

echo "[1/2] hermes CLI healthy"
docker exec "$C" su - hermes -c 'hermes --help >/dev/null 2>&1' || fail "hermes CLI"
echo "  OK"

echo "[2/2] visible Chrome on :1 answering CDP :9222"
docker exec "$C" su - hermes -c \
  'DISPLAY=:1 setsid google-chrome-stable --remote-debugging-port=9222 \
   --user-data-dir=/tmp/cdp-profile about:blank >/dev/null 2>&1 &' || true
sleep 4
docker exec "$C" bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null' || fail "CDP :9222"
echo "  OK"

echo "GO — both checks passed"

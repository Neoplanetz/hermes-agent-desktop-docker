#!/usr/bin/env bash
# The Phase 1 go/no-go gate. All four checks must pass.
set -euo pipefail
C=hermes-desktop
fail() { echo "  FAIL: $1"; exit 1; }

echo "[1/4] hermes computer-use doctor"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null || fail "doctor"
echo "  OK"

echo "[2/4] XTest pointer injection on :1"
docker exec "$C" su - hermes -c 'DISPLAY=:1 xdotool mousemove 640 400'
LOC=$(docker exec "$C" su - hermes -c 'DISPLAY=:1 xdotool getmouselocation --shell')
echo "$LOC" | grep -q '^X=640$' && echo "$LOC" | grep -q '^Y=400$' || fail "XTest move ($LOC)"
echo "  OK"

echo "[3/4] AT-SPI tree readable"
docker exec "$C" su - hermes -c 'DISPLAY=:1 python3 - <<PY
import gi; gi.require_version("Atspi","2.0")
from gi.repository import Atspi
Atspi.init()
assert Atspi.get_desktop(0).get_child_count() >= 1
print("ok")
PY' >/dev/null || fail "AT-SPI tree"
echo "  OK"

echo "[4/4] visible Chrome on :1 answering CDP :9222"
docker exec "$C" su - hermes -c \
  'DISPLAY=:1 setsid google-chrome-stable --remote-debugging-port=9222 \
   --user-data-dir=/tmp/cdp-profile about:blank >/dev/null 2>&1 &' || true
sleep 4
docker exec "$C" bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null' || fail "CDP :9222"
echo "  OK"

echo "GO ✅ — all four checks passed"

#!/usr/bin/env bash
# Passes when Xvnc :1 is up and NoVNC serves the web client.
set -euo pipefail
C=hermes-spike
echo "[verify-desktop] X display :1 present?"
docker exec "$C" su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null' \
  && echo "  OK :1 reachable" || { echo "  FAIL :1"; exit 1; }
echo "[verify-desktop] NoVNC serving on 6080?"
curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null \
  && echo "  OK NoVNC" || { echo "  FAIL NoVNC"; exit 1; }
echo "[verify-desktop] VNC TCP 5901 open?"
docker exec "$C" bash -lc 'ss -ltn | grep -q ":5901"' \
  && echo "  OK 5901" || { echo "  FAIL 5901"; exit 1; }
echo "[verify-desktop] PASS"

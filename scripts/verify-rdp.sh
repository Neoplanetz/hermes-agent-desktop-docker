#!/usr/bin/env bash
# Passes when xrdp is listening on 3389 and its session hook is in place.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp] xrdp listening on 3389?"
docker exec "$C" bash -c 'ss -ltnH "sport = :3389" | grep -q .' && echo "  OK 3389" || { echo "  FAIL 3389"; exit 1; }
echo "[verify-rdp] startwm hook installed + executable?"
docker exec "$C" test -x /etc/xrdp/startwm.sh && echo "  OK startwm" || { echo "  FAIL startwm"; exit 1; }
echo "[verify-rdp] xrdp process healthy (no crash loop)?"
docker exec "$C" pgrep -x xrdp >/dev/null && echo "  OK xrdp running" || { echo "  FAIL xrdp not running"; exit 1; }
echo "[verify-rdp] PASS"

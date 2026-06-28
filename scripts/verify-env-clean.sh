#!/usr/bin/env bash
# Passes when DISPLAY/XAUTHORITY are set for login shells WITHOUT a .bashrc append.
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-env-clean] DISPLAY/XAUTHORITY set for a non-interactive login shell?"
docker exec "$C" su - "$U" -c 'echo "D=$DISPLAY X=$XAUTHORITY"' | grep -q 'D=:1 X=/home/' \
  && echo "  OK display env via profile.d" || { echo "  FAIL display env missing"; exit 1; }
echo "[verify-env-clean] no HERMES DESKTOP DISPLAY block appended to ~/.bashrc?"
docker exec "$C" su - "$U" -c 'grep -q "HERMES DESKTOP DISPLAY" ~/.bashrc 2>/dev/null' \
  && { echo "  FAIL .bashrc still has the inert append"; exit 1; } || echo "  OK .bashrc clean"
echo "[verify-env-clean] no legacy DISPLAY/dbus hack in ~/.profile?"
docker exec "$C" su - "$U" -c 'grep -qiE "DISPLAY=:1|DBUS_SESSION_BUS_ADDRESS|metadata::trusted" ~/.profile 2>/dev/null' \
  && { echo "  FAIL legacy ~/.profile hack present"; exit 1; } || echo "  OK ~/.profile clean"
echo "[verify-env-clean] PASS"

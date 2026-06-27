#!/usr/bin/env bash
# Passes when xrdp is configured to attach to the existing :1 (libvnc → 5901),
# not spawn a new Xorg/Xvnc session.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp-converge] libvnc module present?"
docker exec "$C" bash -c 'ls /usr/lib/xrdp/libvnc.so >/dev/null 2>&1 || ls /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so >/dev/null 2>&1' \
  && echo "  OK libvnc.so" || { echo "  FAIL libvnc.so missing"; exit 1; }
echo "[verify-rdp-converge] xrdp.ini has a session targeting 127.0.0.1:5901 via libvnc?"
docker exec "$C" bash -c 'grep -A8 -iE "^\[.*\]" /etc/xrdp/xrdp.ini | grep -q "lib=libvnc.so" && grep -q "5901" /etc/xrdp/xrdp.ini' \
  && echo "  OK converge session" || { echo "  FAIL no libvnc/5901 session"; exit 1; }
echo "[verify-rdp-converge] PASS (manual: RDP in shows the SAME desktop as NoVNC)"

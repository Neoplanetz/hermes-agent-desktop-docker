#!/usr/bin/env bash
# Passes when xrdp is configured to attach to the existing :1 (libvnc → 5901),
# not spawn a new Xorg/Xvnc session.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp-converge] libvnc module present?"
docker exec "$C" bash -c 'ls /usr/lib/xrdp/libvnc.so >/dev/null 2>&1 || ls /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so >/dev/null 2>&1' \
  && echo "  OK libvnc.so" || { echo "  FAIL libvnc.so missing"; exit 1; }
echo "[verify-rdp-converge] [Hermes-:1] section present in xrdp.ini?"
docker exec "$C" bash -c 'grep -q "^\[Hermes-:1\]" /etc/xrdp/xrdp.ini' \
  && echo "  OK [Hermes-:1] section found" || { echo "  FAIL [Hermes-:1] section missing"; exit 1; }
echo "[verify-rdp-converge] section contains lib=libvnc.so, ip=127.0.0.1, port=5901?"
docker exec "$C" bash -c '
  sec=$(grep -A8 "^\[Hermes-:1\]" /etc/xrdp/xrdp.ini)
  echo "$sec" | grep -q "lib=libvnc.so"  || { echo "FAIL: lib=libvnc.so missing in [Hermes-:1] section"; exit 1; }
  echo "$sec" | grep -q "ip=127.0.0.1"   || { echo "FAIL: ip=127.0.0.1 missing in [Hermes-:1] section"; exit 1; }
  echo "$sec" | grep -q "port=5901"      || { echo "FAIL: port=5901 missing in [Hermes-:1] section"; exit 1; }
' && echo "  OK lib/ip/port in [Hermes-:1] section" || exit 1
echo "[verify-rdp-converge] password in section is expanded (non-empty, not literal \${PASSWORD})?"
docker exec "$C" bash -c '
  sec=$(grep -A8 "^\[Hermes-:1\]" /etc/xrdp/xrdp.ini)
  echo "$sec" | grep -qE "^password=.+" || { echo "FAIL: password line missing or empty in section"; exit 1; }
  if echo "$sec" | grep -qF "password=\${PASSWORD}"; then
    echo "FAIL: password is unexpanded literal \${PASSWORD}"; exit 1
  fi
' && echo "  OK password expanded (not printed)" || exit 1
echo "[verify-rdp-converge] autorun=Hermes-:1 set in [Globals] (default RDP session)?"
docker exec "$C" bash -c 'grep -q "^autorun=Hermes-:1" /etc/xrdp/xrdp.ini' \
  && echo "  OK autorun=Hermes-:1 found in xrdp.ini" || { echo "  FAIL autorun=Hermes-:1 missing — default RDP session not converged"; exit 1; }
echo "[verify-rdp-converge] PASS (manual: RDP login auto-connects to :1, no session-combo selection needed)"

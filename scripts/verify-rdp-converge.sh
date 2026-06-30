#!/usr/bin/env bash
# Passes when xrdp is configured to attach to the existing :1 (libvnc → 5901),
# not spawn a new Xorg/Xvnc session.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp-converge] libvnc module present?"
docker exec "$C" bash -c '[ -f /usr/lib/xrdp/libvnc.so ] || [ -f /usr/lib/x86_64-linux-gnu/xrdp/libvnc.so ] || [ -f /usr/lib/aarch64-linux-gnu/xrdp/libvnc.so ]' \
  && echo "  OK libvnc.so" || { echo "  FAIL libvnc.so missing (checked generic + x86_64 + aarch64 xrdp paths)"; exit 1; }
echo "[verify-rdp-converge] [Hermes] section present in xrdp.ini?"
docker exec "$C" bash -c 'grep -q "^\[Hermes\]" /etc/xrdp/xrdp.ini' \
  && echo "  OK [Hermes] section found" || { echo "  FAIL [Hermes] section missing"; exit 1; }
echo "[verify-rdp-converge] [Hermes] is the FIRST session (before [Xorg])?"
docker exec "$C" bash -c '
  h=$(grep -n "^\[Hermes\]$" /etc/xrdp/xrdp.ini | head -1 | cut -d: -f1)
  x=$(grep -n "^\[Xorg\]$" /etc/xrdp/xrdp.ini | head -1 | cut -d: -f1)
  [ -n "$h" ] && [ -n "$x" ] && [ "$h" -lt "$x" ]
' && echo "  OK [Hermes] precedes [Xorg] (default session)" || { echo "  FAIL [Hermes] not before [Xorg]"; exit 1; }
echo "[verify-rdp-converge] section contains lib=libvnc.so, ip=127.0.0.1, port=5901?"
docker exec "$C" bash -c '
  sec=$(grep -A8 "^\[Hermes\]" /etc/xrdp/xrdp.ini)
  echo "$sec" | grep -q "lib=libvnc.so"  || { echo "FAIL: lib=libvnc.so missing in [Hermes] section"; exit 1; }
  echo "$sec" | grep -q "ip=127.0.0.1"   || { echo "FAIL: ip=127.0.0.1 missing in [Hermes] section"; exit 1; }
  echo "$sec" | grep -q "port=5901"      || { echo "FAIL: port=5901 missing in [Hermes] section"; exit 1; }
' && echo "  OK lib/ip/port in [Hermes] section" || exit 1
echo "[verify-rdp-converge] password in section is expanded (non-empty, not literal \${PASSWORD})?"
docker exec "$C" bash -c '
  sec=$(grep -A8 "^\[Hermes\]" /etc/xrdp/xrdp.ini)
  echo "$sec" | grep -qE "^password=.+" || { echo "FAIL: password line missing or empty in section"; exit 1; }
  if echo "$sec" | grep -qF "password=\${PASSWORD}"; then
    echo "FAIL: password is unexpanded literal \${PASSWORD}"; exit 1
  fi
' && echo "  OK password expanded (not printed)" || exit 1
echo "[verify-rdp-converge] [Hermes] password matches the container's HERMES_PASSWORD?"
docker exec "$C" bash -c '
  sec=$(grep -A8 "^\[Hermes\]" /etc/xrdp/xrdp.ini)
  rdp_pw=$(printf "%s\n" "$sec" | grep "^password=" | head -1 | cut -d= -f2-)
  [ "$rdp_pw" = "${HERMES_PASSWORD:-hermes123}" ]
' && echo "  OK password matches desktop password (not printed)" || { echo "  FAIL [Hermes] password is stale (does not match HERMES_PASSWORD)"; exit 1; }
echo "[verify-rdp-converge] autorun=Hermes set in [Globals] (default RDP session)?"
docker exec "$C" bash -c 'grep -q "^autorun=Hermes$" /etc/xrdp/xrdp.ini' \
  && echo "  OK autorun=Hermes found in xrdp.ini" || { echo "  FAIL autorun=Hermes missing — default RDP session not converged"; exit 1; }
echo "[verify-rdp-converge] PASS (manual: RDP login auto-connects to :1, no session-combo selection needed)"

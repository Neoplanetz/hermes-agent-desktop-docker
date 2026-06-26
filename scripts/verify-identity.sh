#!/usr/bin/env bash
# Passes when the session user + password come from the environment.
set -euo pipefail
C=hermes-desktop
U="${HERMES_USER:-hermes}"
echo "[verify-identity] user '$U' exists, uid>=1000, in sudo?"
docker exec "$C" id "$U" | grep -qE 'uid=[1-9][0-9]{3,}' || { echo "  FAIL uid"; exit 1; }
docker exec "$C" id "$U" | grep -q '(sudo)' || { echo "  FAIL sudo"; exit 1; }
echo "  OK user"
echo "[verify-identity] password matches HERMES_PASSWORD (shadow-hash auth)?"
docker exec -e "U=$U" -e "PW=${HERMES_PASSWORD:-hermes123}" "$C" \
  python3 -W ignore -c 'import crypt,spwd,os,sys; u=os.environ["U"]; pw=os.environ["PW"]; h=spwd.getspnam(u).sp_pwdp; sys.exit(0 if crypt.crypt(pw,h)==h else 1)' \
  && echo "  OK password" || { echo "  FAIL password"; exit 1; }
echo "[verify-identity] PASS"

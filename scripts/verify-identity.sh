#!/usr/bin/env bash
# Passes when the session user + password come from the environment.
set -euo pipefail
C=hermes-desktop
U="${HERMES_USER:-hermes}"
echo "[verify-identity] user '$U' exists, uid>=1000, in sudo?"
docker exec "$C" id "$U" | grep -qE 'uid=(1[0-9]{3,}|[1-9][0-9]{3,})' || { echo "  FAIL uid"; exit 1; }
docker exec "$C" id "$U" | grep -q '(sudo)' || { echo "  FAIL sudo"; exit 1; }
echo "  OK user"
echo "[verify-identity] password matches HERMES_PASSWORD (su auth)?"
docker exec "$C" bash -c "echo '${HERMES_PASSWORD:-hermes123}' | su '$U' -c 'whoami'" | grep -q "^$U$" \
  || { echo "  FAIL password"; exit 1; }
echo "  OK password"
echo "[verify-identity] PASS"

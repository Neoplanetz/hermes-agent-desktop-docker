#!/usr/bin/env bash
# Passes when PID 1 is an init (reaps zombies) and the healthcheck is wired.
set -euo pipefail
C=hermes-desktop
echo "[verify-init] PID 1 is an init (not bash)?"
pid1=$(docker exec "$C" ps -o comm= -p 1 | tr -d ' ')
case "$pid1" in
  *init*|tini|docker-init) echo "  OK pid1=$pid1" ;;
  *) echo "  FAIL pid1=$pid1 (expected an init)"; exit 1 ;;
esac
echo "[verify-init] healthcheck reports a status?"
hs=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$C")
[ "$hs" != "none" ] && echo "  OK health=$hs" || { echo "  FAIL no healthcheck"; exit 1; }
echo "[verify-init] PASS"

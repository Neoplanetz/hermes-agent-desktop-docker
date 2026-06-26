#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose build
docker compose up -d
echo "Waiting for services to settle..."
ready=0
for i in $(seq 1 30); do
  if docker exec hermes-desktop su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'; then
    ready=1; break
  fi
  sleep 1
done
if [[ $ready -eq 0 ]]; then
  echo "ERROR: display :1 did not come up after 30s" >&2
  exit 1
fi
docker compose ps

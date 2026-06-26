#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose build
docker compose up -d
echo "Waiting for services to settle..."
for i in $(seq 1 30); do
  if docker exec hermes-spike su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'; then break; fi
  sleep 1
done
docker compose ps

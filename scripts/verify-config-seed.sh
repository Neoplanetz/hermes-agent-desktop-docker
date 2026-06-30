#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-config-seed] ~/.hermes/config.yaml + SOUL.md present?"
docker exec "$C" su - "$U" -c 'test -f ~/.hermes/config.yaml && test -f ~/.hermes/SOUL.md' \
  && echo "  OK seeded" || { echo "  FAIL missing"; exit 1; }
echo "[verify-config-seed] config has no model pinned (left for runtime)?"
docker exec "$C" su - "$U" -c 'grep -qiE "model:|provider:" ~/.hermes/config.yaml' \
  && { echo "  FAIL model pinned"; exit 1; } || echo "  OK model unset"
echo "[verify-config-seed] PASS"

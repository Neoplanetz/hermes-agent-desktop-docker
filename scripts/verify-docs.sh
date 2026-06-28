#!/usr/bin/env bash
# Passes when the publish-readiness docs exist and cover every access surface.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[verify-docs] .env.example exists with both vars?"
grep -q '^HERMES_USER=' .env.example && grep -q '^HERMES_PASSWORD=' .env.example \
  && echo "  OK .env.example" || { echo "  FAIL .env.example"; exit 1; }
echo "[verify-docs] README covers all four surfaces + default creds?"
for needle in '6080' '5901' '3390' '9119' 'hermes123'; do
  grep -q "$needle" README.md || { echo "  FAIL README missing: $needle"; exit 1; }
done
echo "  OK README"
echo "[verify-docs] DOCKERHUB_OVERVIEW present?"
test -s DOCKERHUB_OVERVIEW.md && echo "  OK overview" || { echo "  FAIL overview"; exit 1; }
echo "[verify-docs] PASS"

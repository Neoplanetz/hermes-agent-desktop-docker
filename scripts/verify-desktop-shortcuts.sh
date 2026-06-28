#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-shortcuts] all three .desktop files present + executable on the Desktop?"
docker exec "$C" su - "$U" -c 'test -x ~/Desktop/hermes-terminal.desktop && test -x ~/Desktop/hermes-setup.desktop && test -x ~/Desktop/hermes-dashboard.desktop' \
  && echo "  OK present" || { echo "  FAIL missing"; exit 1; }
echo "[verify-shortcuts] all three marked trusted (no XFCE untrusted-app prompt)?"
docker exec "$C" su - "$U" -c 'for s in hermes-terminal hermes-setup hermes-dashboard; do gio info ~/Desktop/$s.desktop 2>/dev/null | grep -q "metadata::trusted: true" || exit 1; done' \
  && echo "  OK all trusted" || { echo "  FAIL not trusted"; exit 1; }
echo "[verify-shortcuts] PASS"

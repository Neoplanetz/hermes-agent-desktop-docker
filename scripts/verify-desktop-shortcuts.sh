#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-shortcuts] both .desktop files present + executable on the Desktop?"
docker exec "$C" su - "$U" -c 'test -x ~/Desktop/hermes-terminal.desktop && test -x ~/Desktop/hermes-setup.desktop' \
  && echo "  OK present" || { echo "  FAIL missing"; exit 1; }
echo "[verify-shortcuts] marked trusted (no XFCE untrusted-app prompt)?"
docker exec "$C" su - "$U" -c 'gio info ~/Desktop/hermes-terminal.desktop 2>/dev/null | grep -q "metadata::trusted: true"' \
  && echo "  OK trusted" || { echo "  FAIL not trusted"; exit 1; }
echo "[verify-shortcuts] PASS"

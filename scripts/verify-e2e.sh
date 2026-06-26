#!/usr/bin/env bash
# Fresh named volume → full stack still GO, browser CDP attachable. No model key needed.
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[e2e] dropping volume + fresh boot…"
docker compose down -v >/dev/null 2>&1 || true
./scripts/spike-up.sh >/dev/null
echo "[e2e] waiting for first-boot cua install to complete…"
for i in $(seq 1 120); do
  docker exec "$C" test -f "/home/$U/.hermes/.cua-installed" 2>/dev/null && break
  sleep 2
done
docker exec "$C" test -f "/home/$U/.hermes/.cua-installed" \
  || { echo "  FAIL cua-install timeout (240s)"; exit 1; }
echo "  OK cua installed"
echo "[e2e] go/no-go battery on the fresh volume"
./scripts/verify-gonogo.sh >/dev/null && echo "  OK battery GO" || { echo "  FAIL battery"; exit 1; }
echo "[e2e] config + persona seeded on this fresh volume"
docker exec "$C" su - "$U" -c 'test -f ~/.hermes/config.yaml && test -f ~/.hermes/SOUL.md' \
  && echo "  OK seeded" || { echo "  FAIL seed"; exit 1; }
echo "[e2e] launch visible Chrome on :1 + Hermes /browser connect attaches to :9222"
docker exec "$C" su - "$U" -c \
  'DISPLAY=:1 setsid google-chrome-stable --remote-debugging-port=9222 --user-data-dir=/tmp/e2e about:blank >/dev/null 2>&1 &' || true
sleep 4
docker exec "$C" bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null' \
  && echo "  OK CDP endpoint live (agent-browser /browser connect target)" || { echo "  FAIL CDP"; exit 1; }
echo "[e2e] PASS (automated; model-in-the-loop step is docs/E2E-ACCEPTANCE.md)"

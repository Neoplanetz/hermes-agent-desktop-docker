#!/usr/bin/env bash
# CDP browser leg — assert the RUNTIME wired it up, not the test.
#
# Unlike verify-gonogo / verify-e2e (which launch their OWN Chrome with
# --remote-debugging-port + a /tmp profile to prove the *capability*), this gate
# launches NOTHING: it verifies the entrypoint autostarted a visible Chrome that
# answers CDP on :9222, and that CUA_DRIVER_CDP_PORT reaches login shells so
# cua-driver's `page` tool uses CDP instead of the read-only AT-SPI fallback.
set -euo pipefail
C="${1:-hermes-desktop}"
U="${HERMES_USER:-hermes}"

echo "[cdp] runtime-launched Chrome answers CDP on :9222 (no script-side launch)"
docker exec "$C" bash -lc '
  for i in $(seq 1 20); do
    curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && exit 0
    sleep 2
  done
  exit 1' \
  && echo "  OK :9222 live" \
  || { echo "  FAIL :9222 not answering — entrypoint did not autostart CDP Chrome"; exit 1; }

echo "[cdp] CUA_DRIVER_CDP_PORT=9222 exported to login shells"
docker exec "$C" su - "$U" -c '[ "${CUA_DRIVER_CDP_PORT:-}" = "9222" ]' \
  && echo "  OK CUA_DRIVER_CDP_PORT=9222" \
  || { echo "  FAIL CUA_DRIVER_CDP_PORT not set in login shell"; exit 1; }

echo "[cdp] PASS"

#!/usr/bin/env bash
# Validates the CDP endpoint that Hermes `/browser` attaches to — NOT the full
# `/browser` agent flow (which needs a model key).
#
# Unlike verify-gonogo / verify-e2e (which launch their OWN Chrome with
# --remote-debugging-port + a /tmp profile to prove the *capability*), this gate
# launches NOTHING: it verifies the entrypoint autostarted a visible Chrome that
# answers CDP on :9222 — the endpoint Hermes `/browser` attaches to
# (hermes_cli/browser_connect.py defaults to http://127.0.0.1:9222).
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

echo "[cdp] :9222 is loopback-bound (not 0.0.0.0/::)"
docker exec "$C" bash -lc "ss -ltnH 'sport = :9222' | grep -qE '127\.0\.0\.1:9222' && ! ss -ltnH 'sport = :9222' | grep -qE '0\.0\.0\.0:9222|\[::\]:9222'" \
  && echo "  OK loopback-only" \
  || { echo "  FAIL :9222 not loopback-only"; exit 1; }

echo "[cdp] CDP accepts a new target (Hermes /browser attach surface)"
docker exec "$C" bash -lc 'curl -fsS -X PUT "http://127.0.0.1:9222/json/new?about:blank" >/dev/null' \
  && echo "  OK CDP target-creation works" \
  || { echo "  FAIL CDP did not create a target"; exit 1; }

echo "[cdp] PASS"

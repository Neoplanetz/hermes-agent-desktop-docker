#!/usr/bin/env bash
# Run the full verify-*.sh gate suite against a hermes-desktop container.
#
# Modes:
#   build mode  (default)  : docker compose up -d --build          (amd64 CI + local dev)
#   pull-image  (IMG set)  : docker pull "$IMG"; tag hermes-desktop:latest;
#                            docker compose up -d --no-build        (arm64 CI: verify the
#                            PUBLISHED image on real hardware — the only place arm64 CDP
#                            Chrome runs, since local QEMU emulation core-dumps it)
#
# Usage:
#   scripts/verify-all.sh                                            # build from source
#   IMG=neoplanetz/hermes-desktop-docker:1.1.0 scripts/verify-all.sh # pull + verify
#
# ⚠️ DESTRUCTIVE: tears down with `docker compose down -v`, wiping the hermes-home
# volume (verify-e2e/-persistence already do). Safe on ephemeral CI runners; do NOT
# run against a live local desktop you care about without backing up ~/.hermes first.
#
# Exits non-zero on the first failing gate, naming it.
set -uo pipefail
cd "$(dirname "$0")/.."

C=hermes-desktop
IMG="${IMG:-}"
MODE="build"; [ -n "$IMG" ] && MODE="pull-image"
echo "[verify-all] mode=$MODE${IMG:+ image=$IMG}"

# ---- boot ----------------------------------------------------------------
if [ "$MODE" = "pull-image" ]; then
  echo "[verify-all] pulling $IMG -> tagging hermes-desktop:latest"
  docker pull "$IMG"
  docker tag "$IMG" hermes-desktop:latest
  docker compose up -d --no-build
else
  echo "[verify-all] building image from source"
  docker compose up -d --build
fi

# ---- wait for the compose healthcheck to report healthy ------------------
echo "[verify-all] waiting for container health (compose start_period is 90s)..."
deadline=$((SECONDS + 300))
while :; do
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$C" 2>/dev/null || echo missing)
  case "$status" in
    healthy) echo "[verify-all]   healthy (+${SECONDS}s)"; break ;;
    missing) echo "[verify-all]   FAIL: container $C not found"; docker compose logs --tail 50 || true; exit 1 ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "[verify-all]   FAIL: not healthy within 300s (last status=$status)"
    docker inspect -f '{{json .State.Health}}' "$C" 2>/dev/null || true
    docker compose logs --tail 50 || true
    exit 1
  fi
  sleep 5
done

# ---- run the gates -------------------------------------------------------
# Ordering rules:
#  - verify-cdp BEFORE verify-gonogo/verify-e2e: gonogo/e2e launch extra Chromes on
#    :9222; verify-cdp asserts the autostarted CDP is loopback-only, so it must see
#    only that one.
#  - verify-persistence near the end: it `docker compose up -d --force-recreate`
#    (keeps the volume; no rebuild because hermes-desktop:latest is already present).
#  - verify-e2e LAST and BUILD MODE ONLY: it `docker compose down -v` (wipes the
#    volume) and re-boots via spike-up.sh which `docker compose build`s from source,
#    so it cannot verify a *pulled* image. Native-arm64 CDP is already covered by
#    verify-cdp + verify-gonogo above.
GATES=(identity init desktop rdp rdp-converge cdp gonogo dashboard
       config-seed quiet-boot hermes desktop-shortcuts env-clean slim docs
       persistence)

failed=""
for g in "${GATES[@]}"; do
  echo; echo "===== verify-$g ====="
  if ! ./scripts/verify-"$g".sh; then failed="$g"; break; fi
done

if [ -z "$failed" ]; then
  if [ "$MODE" = "build" ]; then
    echo; echo "===== verify-e2e ====="
    ./scripts/verify-e2e.sh || failed="e2e"
  else
    echo; echo "[verify-all] SKIP verify-e2e in pull-image mode (it rebuilds from"
    echo "             source via spike-up.sh, so it can't verify the pulled image)."
  fi
fi

# ---- teardown ------------------------------------------------------------
echo; echo "[verify-all] tearing down (docker compose down -v)"
docker compose down -v >/dev/null 2>&1 || true

if [ -n "$failed" ]; then
  echo "[verify-all] FAIL at gate: verify-$failed"
  exit 1
fi
echo "[verify-all] ALL GATES PASS (mode=$MODE)"

#!/usr/bin/env bash
# Boot-hygiene gate: AT-SPI daemon is absent (confirming clean AT-SPI removal).
# Run AFTER a fresh boot.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] at-spi-bus-launcher not running?"
docker exec "$C" pgrep -x at-spi-bus-launcher >/dev/null 2>&1 \
  && { echo "  FAIL at-spi-bus-launcher is still running"; exit 1; } || echo "  OK no at-spi-bus-launcher process"
echo "[verify-quiet-boot] PASS"

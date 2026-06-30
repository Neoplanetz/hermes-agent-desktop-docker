#!/usr/bin/env bash
# Boot-hygiene gate: AT-SPI package absent and daemon not running.
# Checks both the dpkg install record and the live process list.
# Run AFTER a fresh boot.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] at-spi2-core package absent?"
docker exec "$C" dpkg-query -W -f='${Status}' at-spi2-core 2>/dev/null | grep -q "install ok installed" \
  && { echo "  FAIL at-spi2-core still installed"; exit 1; } || echo "  OK at-spi2-core absent"
echo "[verify-quiet-boot] at-spi-bus-launcher not running?"
docker exec "$C" pgrep -x at-spi-bus-launcher >/dev/null 2>&1 \
  && { echo "  FAIL at-spi-bus-launcher is still running"; exit 1; } || echo "  OK no at-spi-bus-launcher process"
echo "[verify-quiet-boot] PASS"

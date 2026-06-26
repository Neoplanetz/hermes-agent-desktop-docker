#!/usr/bin/env bash
# Passes when the AT-SPI a11y bus is up and the accessibility tree is readable on :1.
set -euo pipefail
C=hermes-spike
echo "[verify-atspi] a11y bus address resolvable?"
docker exec "$C" su - hermes -c \
  'DISPLAY=:1 dbus-send --session --print-reply --dest=org.a11y.Bus \
   /org/a11y/bus org.a11y.Bus.GetAddress >/dev/null' \
  && echo "  OK a11y bus" || { echo "  FAIL a11y bus"; exit 1; }

echo "[verify-atspi] open a GTK app + read the AT-SPI tree?"
docker exec "$C" su - hermes -c 'DISPLAY=:1 setsid mousepad >/dev/null 2>&1 &' || true
sleep 3
docker exec "$C" su - hermes -c 'DISPLAY=:1 python3 - <<PY
import gi; gi.require_version("Atspi","2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
n = d.get_child_count()
names = [d.get_child_at_index(i).get_name() for i in range(n)]
print("apps:", n, names)
assert n >= 1, "no accessible apps on the desktop"
PY' && echo "  OK AT-SPI tree" || { echo "  FAIL AT-SPI tree"; exit 1; }
echo "[verify-atspi] PASS"

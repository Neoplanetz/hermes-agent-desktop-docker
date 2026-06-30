#!/usr/bin/env bash
# arm64 emulated smoke test for neoplanetz/hermes-desktop-docker
# Boots the arm64 image under QEMU on this amd64 host and polls the same
# health signals the compose healthcheck uses, plus the CDP endpoint.
set -u
IMG="${IMG:-neoplanetz/hermes-desktop-docker:1.1.0-arm64}"
PLATFORM="${PLATFORM:-linux/arm64}"
NAME="${NAME:-hermes-arm64-smoke}"
P_NOVNC="${P_NOVNC:-16080}"
P_DASH="${P_DASH:-19119}"
BUDGET="${BUDGET:-900}"   # seconds; emulation is slow

docker rm -f "$NAME" >/dev/null 2>&1

echo "[smoke] image arch:"
docker image inspect "$IMG" --format '  Architecture={{.Architecture}} Os={{.Os}}' 2>&1 | head -1

echo "[smoke] booting arm64 container (emulated)..."
docker run -d --name "$NAME" --platform "$PLATFORM" \
  -e HERMES_USER=hermes -e HERMES_PASSWORD=hermes123 \
  -p 127.0.0.1:${P_NOVNC}:6080 -p 127.0.0.1:${P_DASH}:9119 \
  --shm-size 2gb --init "$IMG" >/dev/null || { echo "[smoke] FAIL: docker run"; exit 1; }

deadline=$((SECONDS+BUDGET))
n=0; x=0; d=0; c=0; r=0
while [ $SECONDS -lt $deadline ]; do
  state=$(docker inspect -f '{{.State.Status}}' "$NAME" 2>/dev/null)
  if [ "$state" = "exited" ]; then
    echo "[smoke] FAIL: container exited early"; docker logs --tail 50 "$NAME" 2>&1; exit 1
  fi
  [ $n -eq 0 ] && docker exec "$NAME" sh -c 'curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null 2>&1' && { n=1; echo "[smoke] OK  NoVNC 6080 (+$SECONDS s)"; }
  [ $x -eq 0 ] && docker exec "$NAME" su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && { x=1; echo "[smoke] OK  X display :1 (+$SECONDS s)"; }
  [ $d -eq 0 ] && docker exec "$NAME" sh -c "ss -ltnH 'sport = :9119' | grep -q ." && { d=1; echo "[smoke] OK  dashboard 9119 (+$SECONDS s)"; }
  [ $c -eq 0 ] && docker exec "$NAME" sh -c 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1' && { c=1; echo "[smoke] OK  CDP Chrome 9222 (+$SECONDS s)"; }
  [ $r -eq 0 ] && docker exec "$NAME" pgrep -x xrdp >/dev/null 2>&1 && { r=1; echo "[smoke] OK  xrdp (+$SECONDS s)"; }
  if [ $((n+x+d+c+r)) -eq 5 ]; then echo "[smoke] ALL PASS at +$SECONDS s"; break; fi
  sleep 15
done

echo "[smoke] summary: novnc=$n xdisplay=$x dashboard=$d cdp=$c xrdp=$r"
echo "[smoke] --- container state ---"; docker inspect -f '{{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$NAME" 2>&1
echo "[smoke] --- last 30 log lines ---"; docker logs --tail 30 "$NAME" 2>&1
[ $((n+x+d+c+r)) -eq 5 ] && exit 0 || exit 2

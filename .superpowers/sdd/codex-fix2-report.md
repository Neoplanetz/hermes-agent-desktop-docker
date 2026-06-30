# Codex 2nd Review Fix Report — 2026-06-30

## Summary

Applied all 5 edits from the second Codex review of the AT-SPI/XTest-removal commits, rebuilt the image, and verified all gates PASS.

---

## Edits Applied

### 1 (Important) entrypoint.sh — neutralize stale a11y `.xprofile` on pre-existing volumes

Inserted after the `chown -R "$USER:$USER" "/home/$USER"` line in the first-boot home seed section:

```sh
# ── Clean stale a11y .xprofile from pre-v2B volumes ──
su - "$USER" -c 'if [ -f ~/.xprofile ] && grep -qE "atk-bridge|NO_AT_BRIDGE|QT_ACCESSIBILITY" ~/.xprofile; then rm -f ~/.xprofile; fi'
```

File: `entrypoint.sh` (between the home-seed section and the Desktop shortcuts section).

### 2 (Important) scripts/verify-persistence.sh — drop `.xprofile` from seed check

Changed:
```
test -f ~/.vnc/xstartup && test -f ~/.xprofile
```
To:
```
test -f ~/.vnc/xstartup
```

File: `scripts/verify-persistence.sh` line 9.

### 3 (Minor) scripts/verify-quiet-boot.sh — accurate comment + package-absence assertion

Updated header comment from the over-claiming "confirming clean AT-SPI removal" to "Checks both the dpkg install record and the live process list." Added a `dpkg-query` check for `at-spi2-core` alongside the existing `pgrep` check.

File: `scripts/verify-quiet-boot.sh`.

### 4 (Minor) scripts/verify-config-seed.sh — word-boundary-anchored cua negative-grep

Changed the pattern from:
```
grep -qiE "computer_use|computer-use|cua|CUA_DRIVER"
```
To:
```
grep -qiE "(^|[^[:alnum:]_])(computer_use|computer-use|cua|CUA_DRIVER)([^[:alnum:]_]|$)"
```
Also changed `su - "$U" -c '...'` to `sh -c '...'` since the file being grepped is at an absolute path in the container (not relative to the user home).

File: `scripts/verify-config-seed.sh` line 11-12.

### 5 (Minor) docs/superpowers/plans/2026-06-30-public-cdp-scope-implementation.md — historical banner

Added at the very top (line 1):
```
> ⚠️ **HISTORICAL / SUPERSEDED.** This plan captured the cua-driver-removal round. Two later review rounds changed the end state: `9222` was removed from `EXPOSE` (CDP is loopback-only), `scripts/verify-atspi.sh` was deleted, and the AT-SPI/XTest tooling was removed. Treat specifics below as point-in-time; the repo is the source of truth.
```

---

## Build

```
docker build -t hermes-desktop:latest .
```
Result: SUCCESS (layer 16/17 rebuilt for entrypoint.sh change; all other layers cached).

---

## Container Health

```
docker compose up -d --force-recreate
docker ps --filter name=hermes-desktop
```
Result: `Up 14 seconds (healthy)` — container healthy on first poll.

---

## .xprofile Cleanup Evidence

The live `hermes-home` volume predates the a11y removal and carried the old `~/.xprofile`. After `--force-recreate`:

```
$ docker exec hermes-desktop su - hermes -c 'test -f ~/.xprofile && echo XPROFILE_STILL_PRESENT || echo XPROFILE_REMOVED'
XPROFILE_REMOVED
```

Cleanup fired correctly — the file was matched by the a11y marker grep and removed.

---

## Gate Results (all PASS)

| Gate | Result |
|------|--------|
| `verify-persistence.sh` | PASS |
| `verify-quiet-boot.sh` | PASS (at-spi2-core absent + no at-spi-bus-launcher process) |
| `verify-config-seed.sh` | PASS |
| `verify-gonogo.sh` | PASS (GO) |
| `verify-cdp.sh` | PASS |

### verify-persistence output
```
[verify-persistence] /home/hermes is a mount (volume)?
  OK mounted
[verify-persistence] template-seeded files present on this volume?
  OK seeded
[verify-persistence] write marker, recreate container, marker survives?
  OK persisted across recreate
[verify-persistence] PASS
```

### verify-quiet-boot output
```
[verify-quiet-boot] at-spi2-core package absent?
  OK at-spi2-core absent
[verify-quiet-boot] at-spi-bus-launcher not running?
  OK no at-spi-bus-launcher process
[verify-quiet-boot] PASS
```

### verify-config-seed output
```
[verify-config-seed] ~/.hermes/config.yaml + SOUL.md present?
  OK seeded
[verify-config-seed] image seed pins no model (left for runtime)?
  OK model unset in image seed
[verify-config-seed] image seed has no computer_use/cua re-introduced?
  OK seed clean
[verify-config-seed] PASS
```

### verify-gonogo output
```
[1/2] hermes CLI healthy
  OK
[2/2] visible Chrome on :1 answering CDP :9222
  OK
GO — both checks passed
```

### verify-cdp output
```
[cdp] runtime-launched Chrome answers CDP on :9222 (no script-side launch)
  OK :9222 live
[cdp] :9222 is loopback-bound (not 0.0.0.0/::)
  OK loopback-only
[cdp] CDP accepts a new target (Hermes /browser attach surface)
  OK CDP target-creation works
[cdp] PASS
```

---

## Concerns

None. All edits applied cleanly, build succeeded from cache, container came up healthy on first boot, and the pre-existing volume's stale `.xprofile` was correctly detected and removed.

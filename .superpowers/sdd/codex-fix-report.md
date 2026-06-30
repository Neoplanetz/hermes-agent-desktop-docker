# Codex Review Fix Report
Date: 2026-06-30

## Summary
All 10 edits applied, build succeeded, container healthy, CDP_OK, all 4 gates PASS.

---

## Edits Applied

### 1 (I-1a) entrypoint.sh — loopback CDP bind
**File:** `entrypoint.sh`
**Before:**
```
  --remote-debugging-port=9222 --remote-allow-origins=* \
```
**After:**
```
  --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 --remote-allow-origins=* \
```

### 2 (Q-1) entrypoint.sh — justify wide allow-origins
**File:** `entrypoint.sh`
Added comment immediately above the Chrome launch line:
```
# --remote-allow-origins=* is required for the CDP websocket handshake on Chrome 136+, and is safe because CDP is bound to loopback (--remote-debugging-address=127.0.0.1) — only local clients can reach it.
```

### 3 (M-1a) entrypoint.sh — rename CDP profile dir
**File:** `entrypoint.sh`
**Before:** `CDP_PROFILE="/home/$USER/.config/google-chrome-cua"`
**After:** `CDP_PROFILE="/home/$USER/.config/google-chrome-cdp"`

### 4 (M-1b) Dockerfile — fix stale comment
**File:** `Dockerfile` (~line 50)
**Before:** `# Browser with a --no-sandbox \`google-chrome-stable\` wrapper (CDP/computer-use).`
**After:** `# Browser with a --no-sandbox \`google-chrome-stable\` wrapper (CDP).`

### 5 (I-1b) Dockerfile — drop 9222 from EXPOSE
**File:** `Dockerfile`
**Before:** `EXPOSE 6080 5901 9222 3389 9119`
**After:** `EXPOSE 6080 5901 3389 9119`

### 6 (I-1c + I-2) scripts/verify-cdp.sh — loopback assertion + scope comment
**File:** `scripts/verify-cdp.sh`
- Updated top comment: now states it validates the CDP endpoint that Hermes `/browser` attaches to — NOT the full `/browser` agent flow.
- Added after `:9222 live` check:
```bash
echo "[cdp] :9222 is loopback-bound (not 0.0.0.0/::)"
docker exec "$C" bash -lc "ss -ltnH 'sport = :9222' | grep -qE '127\.0\.0\.1:9222' && ! ss -ltnH 'sport = :9222' | grep -qE '0\.0\.0\.0:9222|\[::\]:9222'" \
  && echo "  OK loopback-only" \
  || { echo "  FAIL :9222 not loopback-only"; exit 1; }
```

### 7 (I-2) scripts/verify-e2e.sh — clarify CDP check comment
**File:** `scripts/verify-e2e.sh`
**Before:** `&& echo "  OK CDP endpoint live (agent-browser /browser connect target)"`
**After:** `&& echo "  OK CDP endpoint live (confirms the surface /browser attaches to — not a full /browser agent run)"`

### 8 (I-3) scripts/verify-config-seed.sh — negative-assert no cua re-enters image seed
**File:** `scripts/verify-config-seed.sh`
Added before the final PASS line (checks only the image seed `/opt/hermes-defaults/.hermes/config.yaml`, NOT live `~/.hermes/config.yaml`):
```bash
echo "[verify-config-seed] image seed has no computer_use/cua re-introduced?"
docker exec "$C" su - "$U" -c 'grep -qiE "computer_use|computer-use|cua|CUA_DRIVER" /opt/hermes-defaults/.hermes/config.yaml' \
  && { echo "  FAIL cua/computer_use back in image seed"; exit 1; } || echo "  OK seed clean"
```

### 9 (I-4) docs/E2E-ACCEPTANCE.md — ARCHIVED banner
**File:** `docs/E2E-ACCEPTANCE.md`
Added at line 1 (above existing first heading):
```
> ⚠️ **ARCHIVED / HISTORICAL.** This document records the now-removed `computer_use` / cua-driver investigation. The shipped image provides **CDP browser automation only** (cua-driver was removed). Procedures below that reference `hermes -t computer_use chat` or `CUA_DRIVER_CDP_PORT` no longer apply — they are kept for the root-cause analysis (why native desktop input was descoped).
```

### 10 (M-2) docs/ACCESS-MODEL.md — fix stale RDP section names
**File:** `docs/ACCESS-MODEL.md`
**Before:** `[Hermes-:1]` and `autorun=Hermes-:1`
**After:** `[Hermes]` and `autorun=Hermes`

---

## Verification Evidence

### Bash syntax check
```
bash -n entrypoint.sh scripts/verify-cdp.sh scripts/verify-config-seed.sh scripts/verify-e2e.sh
→ exit 0 (syntax OK)
```

### Docker build
```
docker build -t hermes-desktop:latest .
→ #22 naming to docker.io/library/hermes-desktop:latest done
→ Build succeeded (layers 16-17 rebuilt for entrypoint.sh change; all others cached)
```

### Container health
```
docker compose up -d --force-recreate
→ healthy after ~14s
docker logs hermes-desktop → no traceback/Chrome-singleton errors
```

### CDP_OK confirmation
```
docker exec hermes-desktop bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null && echo CDP_OK'
→ CDP_OK
```

### Loopback bind evidence (ss output)
```
docker exec hermes-desktop bash -lc "ss -ltnH 'sport = :9222'"
LISTEN 0      10     127.0.0.1:9222 0.0.0.0:*
LISTEN 0      10         [::1]:9222    [::]:*
```
Both IPv4 and IPv6 bind to loopback only. 0.0.0.0 and [::] are absent.

### Gate results
| Gate | Result |
|---|---|
| `scripts/verify-cdp.sh hermes-desktop` (incl. loopback assertion) | PASS |
| `scripts/verify-config-seed.sh hermes-desktop` (incl. cua negative-grep) | PASS |
| `scripts/verify-gonogo.sh hermes-desktop` | PASS |
| `scripts/verify-docs.sh` | PASS |

### verify-cdp.sh full output
```
[cdp] runtime-launched Chrome answers CDP on :9222 (no script-side launch)
  OK :9222 live
[cdp] :9222 is loopback-bound (not 0.0.0.0/::)
  OK loopback-only
[cdp] CDP accepts a new target (Hermes /browser attach surface)
  OK CDP target-creation works
[cdp] PASS
```

### verify-config-seed.sh full output
```
[verify-config-seed] ~/.hermes/config.yaml + SOUL.md present?
  OK seeded
[verify-config-seed] image seed pins no model (left for runtime)?
  OK model unset in image seed
[verify-config-seed] image seed has no computer_use/cua re-introduced?
  OK seed clean
[verify-config-seed] PASS
```

### verify-gonogo.sh full output
```
[1/4] hermes CLI healthy (no cua-driver required)
  OK
[2/4] XTest pointer injection on :1
  OK
[3/4] AT-SPI tree readable
  OK
[4/4] visible Chrome on :1 answering CDP :9222
  OK
GO ✅ — all four checks passed
```

### verify-docs.sh full output
```
[verify-docs] .env.example exists with both vars?
  OK .env.example
[verify-docs] README covers all four surfaces + default creds?
  OK README
[verify-docs] DOCKERHUB_OVERVIEW present?
  OK overview
[verify-docs] PASS
```

---

## Concerns / Notes
- Chrome on arm64 uses the xtradeb Chromium wrapper; the `--remote-debugging-address` flag is forwarded correctly through the `google-chrome-stable` wrapper script.
- The profile dir rename (`google-chrome-cua` → `google-chrome-cdp`) creates a fresh dir on existing volumes, which is intentional (throwaway browser profile, no state to preserve).
- `verify-e2e.sh` was NOT run (its `down -v` wipes the volume, as instructed).

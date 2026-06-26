# Phase 1 Spike — Go/No-Go Verdict

**Verdict: GO — TigerVNC `Xvnc :1`**

All four go/no-go checks passed. The computer-use desktop product is viable on TigerVNC; proceed to Phase 2 (full image port).

---

## Battery Results

### [1/4] `hermes computer-use doctor`

Exit code: **0** (PASS)

```
✅ cua-driver 0.6.8 on linux — ok
  ✅ binary_version: cua-driver 0.6.8
  ✅ platform_supported: Ubuntu 24.04.4 LTS (x86_64)
      architecture=x86_64
      os_version=Ubuntu 24.04.4 LTS
  ✅ session_active: MCP session is active.
  ⏭️ bundle_identity: not applicable on Linux
  ⏭️ tcc_accessibility: not applicable on Linux
  ⏭️ tcc_screen_recording: not applicable on Linux
  ✅ ax_capability: X11 reachable; AT-SPI + XSendEvent input will work.
  ✅ screen_capture_capability: X11 reachable; screen capture path is functional.
  ⏭️ wayland_backend: No WAYLAND_DISPLAY in the environment — not a Wayland session.
```

### [2/4] XTest pointer injection on `:1`

Command: `DISPLAY=:1 xdotool mousemove 640 400` then `xdotool getmouselocation --shell`

Result (PASS):

```
X=640
Y=400
SCREEN=0
WINDOW=14680104
```

### [3/4] AT-SPI tree readable

Desktop child count: **9** (PASS — requirement is ≥ 1)

```
AT-SPI desktop child count: 9
  app[0]: xfce4-session
  app[1]: xfwm4
  app[2]: xfsettingsd
  app[3]: xfce4-panel
  app[4]: Thunar
  app[5]: xfdesktop
  app[6]: wrapper-2.0
  app[7]: wrapper-2.0
  app[8]: wrapper-2.0
```

### [4/4] Visible Chrome on `:1` answering CDP `:9222`

`curl http://127.0.0.1:9222/json/version` result (PASS):

```json
{
   "Browser": "Chrome/149.0.7827.200",
   "Protocol-Version": "1.3",
   "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
   "V8-Version": "14.9.207.35",
   "WebKit-Version": "537.36 (@c35c164b1b6d1adca9eddf914ed6d0d0743dba6a)",
   "webSocketDebuggerUrl": "ws://127.0.0.1:9222/devtools/browser/a70d5691-dc8e-47fe-87bd-982ce79033bb"
}
```

---

## Known Cosmetic Issue: cua-driver systemd-unit warning

During container boot, a warning appears: `"cua-driver installing did not complete"`. This is **cosmetic only** and not a functional failure.

**Root cause:** `hermes computer-use install` successfully installs the cua-driver binary, but its background-service sub-step attempts to register a **systemd user unit**, which fails in this no-systemd container. cua-driver operates in on-demand **MCP mode** regardless, and `hermes computer-use doctor` confirms this works correctly (exit 0, all applicable checks green).

This is not a startup race and not an autostart conflict — no hermes or cua `.desktop` file exists in any XDG autostart directory. The failure is purely the systemd registration step.

**Phase-2 follow-up:** either suppress the post-install systemd-unit step (pass a flag / skip the service registration sub-command), or document it in the README as expected behavior in container deployments.

---

## Phase 2 Follow-Ups

1. **cua-driver systemd-unit warning:** suppress the unit-registration step or settle cua-driver lifecycle for containerized no-systemd environments; on-demand MCP mode is sufficient for Phase 2.
2. **Pin Hermes to a tag/commit:** replace `--branch main` with a pinned release tag or commit SHA to ensure reproducible builds.
3. **Slim the image (multi-stage):** drop `build-essential` and other build-time deps after the Hermes install layer; `--skip-browser` is already used. Potential ~200 MB saving.
4. **Suppress the `gail` GTK3 no-op warning:** the `GTK_MODULES=gail:atk-bridge` entry in `.xprofile` causes a benign GTK3 "gail module not found" log; replace with `atk-bridge` only.
5. **`chown`-every-boot:** `entrypoint.sh` re-chowns `~/.hermes` and `~/.bashrc` on each start; this is harmless but redundant once the Dockerfile creates them. Move to build time.
6. **`verify-hermes.sh` output assertion:** the script checks exit code only; add a grep for a known-good string in the `hermes --version` output as a belt-and-suspenders check.
7. **`$USER` defaults in entrypoint:** the hardcoded `USER=hermes` at the top of `entrypoint.sh` could be replaced with `${USER:-hermes}` to support image re-use with a different username.
8. **Drop redundant `ENV HERMES_HOME`:** `HERMES_HOME=/root/.hermes` is set in the Dockerfile but Hermes runs as `hermes` (uid 1000); the env var is never used at runtime and may mislead.

---

## Summary

| Check | Result |
|-------|--------|
| `hermes computer-use doctor` | PASS (exit 0) |
| XTest pointer injection (xdotool) | PASS (X=640, Y=400) |
| AT-SPI tree readable | PASS (9 apps) |
| Chrome CDP `:9222` | PASS (Chrome 149) |
| **Overall** | **GO** |

Display backend: **TigerVNC `Xvnc :1`** (Xvfb fallback was not needed).

Image: `hermes-desktop-spike:latest` · Container: `hermes-spike` · User: `hermes` (uid 1000) · Display: `:1`

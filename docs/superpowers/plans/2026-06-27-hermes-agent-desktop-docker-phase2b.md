> ⚠️ **HISTORICAL — pre-pivot.** This document predates the **2026-06-30 pivot** to a public image. It describes the original `computer_use` / **cua-driver** native desktop-input ambition (AT-SPI tree + XTest), which was **proven insecure under this VNC/container model and dropped** — native desktop input is now a documented **non-goal**. The shipped product is **secure, zero-privilege CDP browser automation** (Hermes `/browser` → CDP Chrome on loopback `127.0.0.1:9222`). Current truth: `docs/superpowers/specs/2026-06-30-public-cdp-scope-design.md`, the README “Known limitations,” and the repo itself.

# Hermes Agent Desktop Docker — Phase 2B: Full Remote-Desktop Shell

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the remote-desktop shell on top of the persistent 2A base — proper PID-1 init (zombie reaping + clean shutdown + dead-service detection), RDP access that **converges on the agent's `:1` desktop** (so `computer_use` is observable over RDP as well as NoVNC/VNC), and desktop shortcuts to drive Hermes — bringing OpenClaw-parity access without OpenClaw's dynamic display-sync.

**Architecture:** Continue on the repo `/home/neoplanetz/Documents/github/hermes-agent-desktop-docker` (`main`, at `6edf1ab`). **Init decision: Docker's built-in init (`init: true`, i.e. tini) — NOT a full s6-overlay migration.** Rationale: the entrypoint is already sequential, so `hermes computer-use install` completes before any later service (the 2C dashboard) starts — the "dashboard depends on cua" ordering the 2A review wanted is satisfied by ordering, not supervision. `init: true` adds the missing pieces (zombie reaping + signal forwarding for clean `docker stop`); a compose healthcheck adds dead-service detection. Full s6 supervision stays a deferred option (revisit only if parallel service supervision is genuinely needed). Each task keeps the TDD-style cycle: write `scripts/verify-*.sh` → run/fail → implement → rebuild → pass → commit, and re-runs `verify-gonogo.sh` so the computer_use stack never regresses.

**Tech Stack:** Docker (linux/amd64), Ubuntu 24.04, XFCE4, TigerVNC `Xvnc :1`, NoVNC, **xRDP + libvnc backend**, Docker init (tini), Hermes/cua-driver.

## Global Constraints

- **Display `:1` is the single canvas.** NoVNC (6080) and raw VNC (5901) already show it. RDP (3389) must converge on `:1` (Task 3) — not spawn a second XFCE session — so the agent's `computer_use` actions are visible regardless of access method. Documented fallback if libvnc convergence proves fiddly: RDP serves a *separate* session and we document "observe computer_use over NoVNC/VNC."
- **Do not regress 2A.** After every task, `./scripts/verify-gonogo.sh` must still end `GO ✅`, and the persistence/identity/config gates must still pass. `entrypoint.sh` keeps `set -euo pipefail`.
- **Identity/persistence unchanged:** session user `${HERMES_USER:-hermes}` (uid 1000), named `hermes-home` volume, first-boot seed from `/opt/hermes-defaults`. New home files (xRDP `.xsession`, desktop shortcuts) seed through that same template/chown path.
- **Naming:** image/container `hermes-desktop`. Ports: 6080 (NoVNC), 5901 (VNC), **3389 (RDP)** newly host-published (bind `127.0.0.1` only, like the others). 9119/8642 remain for 2C.
- **No secrets baked** beyond the published dev default `hermes123`. The VNC password (= `HERMES_PASSWORD`) is generated at runtime; any xrdp→VNC auto-connect must read it at runtime, never bake it into a tracked file.
- **Docker env:** logged OUT of Docker Hub (anonymous pulls of cached `ubuntu:24.04` work). Build/run via `./scripts/spike-up.sh`. Re-`docker login` only before a 2C image push.

---

### Task 1: PID-1 init (zombie reaping + clean shutdown) + healthcheck

**Files:**
- Modify: `<repo>/docker-compose.yml` (`init: true` + `healthcheck`)
- Create: `<repo>/scripts/verify-init.sh`

**Interfaces:**
- Produces: container reaps zombies and stops cleanly; `docker inspect` reports a health status driven by `:1` + NoVNC liveness.

- [ ] **Step 1: Write the failing test — `scripts/verify-init.sh`**

```bash
#!/usr/bin/env bash
# Passes when PID 1 is an init (reaps zombies) and the healthcheck is wired.
set -euo pipefail
C=hermes-desktop
echo "[verify-init] PID 1 is an init (not bash)?"
pid1=$(docker exec "$C" ps -o comm= -p 1 | tr -d ' ')
case "$pid1" in
  *init*|tini|docker-init) echo "  OK pid1=$pid1" ;;
  *) echo "  FAIL pid1=$pid1 (expected an init)"; exit 1 ;;
esac
echo "[verify-init] healthcheck reports a status?"
hs=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$C")
[ "$hs" != "none" ] && echo "  OK health=$hs" || { echo "  FAIL no healthcheck"; exit 1; }
echo "[verify-init] PASS"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/verify-init.sh`
Expected: FAIL — PID 1 is `bash` (the entrypoint), no healthcheck.

- [ ] **Step 3: Add `init: true` + `healthcheck` to `docker-compose.yml`**

Under the `hermes-desktop` service:

```yaml
    init: true
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null && su - \"${HERMES_USER:-hermes}\" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s
```

> `init: true` makes Docker run its bundled init (tini) as PID 1 — reaping zombies and forwarding signals so `docker stop` is clean — while our `entrypoint.sh` runs as its child unchanged. `start_period: 90s` covers cold-boot + first-boot cua-install before failures count.

- [ ] **Step 4: Rebuild + verify**

Run: `./scripts/spike-up.sh && sleep 5 && ./scripts/verify-init.sh`
Expected: `[verify-init] PASS` (pid1 is `docker-init`/`tini`; health reports `starting`/`healthy`). Then `./scripts/verify-gonogo.sh` → still `GO ✅`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(2b): Docker init (tini) PID1 + :1/NoVNC healthcheck"
```

---

### Task 2: xRDP — baseline RDP access (separate session)

**Files:**
- Modify: `<repo>/Dockerfile` (apt `xrdp xorgxrdp`; `.xsession`; template)
- Modify: `<repo>/entrypoint.sh` (start xRDP; regenerate session hook)
- Modify: `<repo>/docker-compose.yml` (publish `127.0.0.1:3389:3389`)
- Create: `<repo>/configs/xrdp/startwm.sh`
- Create: `<repo>/scripts/verify-rdp.sh`

**Interfaces:**
- Consumes: the 2A entrypoint + Task 1 init.
- Produces: xRDP listening on 3389; an RDP login (for `${HERMES_USER}`) yields an XFCE session. This task uses the **known-working separate-session** path; Task 3 converges it onto `:1`.

- [ ] **Step 1: Write the failing test — `scripts/verify-rdp.sh`**

```bash
#!/usr/bin/env bash
# Passes when xrdp is listening on 3389 and its session hook is in place.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp] xrdp listening on 3389?"
docker exec "$C" bash -c 'ss -ltn | grep -q ":3389"' && echo "  OK 3389" || { echo "  FAIL 3389"; exit 1; }
echo "[verify-rdp] startwm hook installed + executable?"
docker exec "$C" test -x /etc/xrdp/startwm.sh && echo "  OK startwm" || { echo "  FAIL startwm"; exit 1; }
echo "[verify-rdp] xrdp process healthy (no crash loop)?"
docker exec "$C" pgrep -x xrdp >/dev/null && echo "  OK xrdp running" || { echo "  FAIL xrdp not running"; exit 1; }
echo "[verify-rdp] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-rdp.sh` → FAIL (xrdp not installed).

- [ ] **Step 3: Install xRDP in the `Dockerfile`**

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      xrdp xorgxrdp \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# Session hook (separate XFCE session; Task 3 converges onto :1 via libvnc)
COPY configs/xrdp/startwm.sh /etc/xrdp/startwm.sh
RUN chmod +x /etc/xrdp/startwm.sh \
    && sed -i 's/^#xserverbpp=24/xserverbpp=24/' /etc/xrdp/xrdp.ini || true
```

- [ ] **Step 4: Write `configs/xrdp/startwm.sh`** (XFCE session, no OpenClaw display-sync)

```bash
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
[ -r /etc/profile ] && . /etc/profile
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"
exec dbus-launch --exit-with-session startxfce4
```

- [ ] **Step 5: Start xRDP in `entrypoint.sh`** — after the VNC/NoVNC block, before the cua block (so RDP is up early). Per-user `.xsession`, TLS-key perms, start daemons:

```bash
# ── xRDP (RDP access on 3389) ──
echo "xfce4-session" > "/home/$USER/.xsession"
chown "$USER:$USER" "/home/$USER/.xsession"
[ -f /etc/xrdp/rsakeys.ini ] || xrdp-keygen xrdp /etc/xrdp/rsakeys.ini 2>/dev/null || true
if [ -f /etc/xrdp/key.pem ]; then
    chmod 640 /etc/xrdp/key.pem
    chgrp ssl-cert /etc/xrdp/key.pem 2>/dev/null || chmod 644 /etc/xrdp/key.pem
fi
/etc/init.d/xrdp start 2>/dev/null || { xrdp-sesman; xrdp; } || true
```

- [ ] **Step 6: Publish 3389** in `docker-compose.yml`: add `- "127.0.0.1:3389:3389"` to `ports`.

- [ ] **Step 7: Rebuild + verify**

Run: `./scripts/spike-up.sh && sleep 5 && ./scripts/verify-rdp.sh`
Expected: `[verify-rdp] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅`. (Optional manual: connect an RDP client to `localhost:3389`, log in as `hermes`/`hermes123`, confirm an XFCE desktop — at this point a *separate* session from `:1`.)

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(2b): xRDP access on 3389 (separate session baseline)"
```

---

### Task 3: Converge RDP onto `:1` (libvnc passthrough) — with documented fallback

**Files:**
- Modify: `<repo>/Dockerfile` / `<repo>/entrypoint.sh` (xrdp libvnc session pointing at `127.0.0.1:5901`)
- Create: `<repo>/configs/xrdp/xrdp.ini.append` (or an entrypoint-generated session block)
- Create: `<repo>/scripts/verify-rdp-converge.sh`
- Modify: `<repo>/docs/` (note the access model)

**Interfaces:**
- Consumes: Task 2's xRDP + the running TigerVNC `:1` on 5901.
- Produces: an RDP connection attaches to the **existing `:1`** (same desktop as NoVNC/VNC), so `computer_use` is visible over RDP. OR the documented fallback.

- [ ] **Step 1: Write the failing test — `scripts/verify-rdp-converge.sh`**

```bash
#!/usr/bin/env bash
# Passes when xrdp is configured to attach to the existing :1 (libvnc → 5901),
# not spawn a new Xorg/Xvnc session.
set -euo pipefail
C=hermes-desktop
echo "[verify-rdp-converge] libvnc module present?"
docker exec "$C" bash -c 'ls /usr/lib/xrdp/libvnc.so >/dev/null 2>&1' \
  && echo "  OK libvnc.so" || { echo "  FAIL libvnc.so missing"; exit 1; }
echo "[verify-rdp-converge] xrdp.ini has a session targeting 127.0.0.1:5901 via libvnc?"
docker exec "$C" bash -c 'grep -A8 -iE "^\[.*\]" /etc/xrdp/xrdp.ini | grep -q "lib=libvnc.so" && grep -q "5901" /etc/xrdp/xrdp.ini' \
  && echo "  OK converge session" || { echo "  FAIL no libvnc/5901 session"; exit 1; }
echo "[verify-rdp-converge] PASS (manual: RDP in shows the SAME desktop as NoVNC)"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-rdp-converge.sh` → FAIL.

- [ ] **Step 3: Add a libvnc session to `xrdp.ini`** that auto-connects to `:1`. The xrdp `libvnc.so` module connects to an existing VNC server. Append a session block (via the Dockerfile or entrypoint) — read the VNC password at runtime (do NOT bake it):

Entrypoint (after the VNC password file is written, before xrdp start), generate the block with the runtime password:

```bash
# Converge RDP onto the existing :1 (TigerVNC on 5901) via libvnc.
# Replaces the default Xorg session so an RDP login lands on :1.
if [ -f /usr/lib/xrdp/libvnc.so ]; then
  cat > /etc/xrdp/xrdp.ini.d-hermes <<RDPCONV || true
[Hermes-:1]
name=Hermes Desktop (:1)
lib=libvnc.so
username=na
password=${PASSWORD}
ip=127.0.0.1
port=5901
RDPCONV
  # Splice our session to the top of the [Globals]→sessions list (idempotent)
  if ! grep -q '^\[Hermes-:1\]' /etc/xrdp/xrdp.ini; then
    cat /etc/xrdp/xrdp.ini.d-hermes >> /etc/xrdp/xrdp.ini
  fi
  chmod 600 /etc/xrdp/xrdp.ini
fi
```

> Security note: this writes the VNC password into `/etc/xrdp/xrdp.ini` at runtime (mode 600, root-only, inside the container) — it is NOT a tracked file and not in the image. Acceptable for the published-dev-default model; documented for LAN-exposure users.

- [ ] **Step 4: Rebuild + verify (automated + manual)**

Run: `./scripts/spike-up.sh && sleep 5 && ./scripts/verify-rdp-converge.sh`
Expected automated: `PASS`. **Manual (the real proof):** RDP to `localhost:3389`, pick the `Hermes Desktop (:1)` session → you should see the SAME desktop as NoVNC (same windows, same cursor). Open a window in NoVNC, confirm it appears in the RDP view. Then `./scripts/verify-gonogo.sh` → `GO ✅`.

- [ ] **Step 5: If convergence is fiddly — DOCUMENT the fallback (do not block 2B)**

If the libvnc session won't auto-attach cleanly (auth prompt loops, black screen), revert Step 3 (keep Task 2's separate-session RDP) and write `docs/ACCESS-MODEL.md` stating: **the agent acts on `:1`; observe `computer_use` over NoVNC (`http://localhost:6080`) or a raw VNC client (`localhost:5901`); RDP (`localhost:3389`) is a separate general-use session.** Make `verify-rdp-converge.sh` skip-with-explanation in that case (exit 0 + a clear `SKIP: RDP separate-session fallback (see docs/ACCESS-MODEL.md)` line) so the suite stays honest. Record which path shipped.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(2b): converge RDP onto :1 via libvnc (or documented separate-session fallback)"
```

---

### Task 4: Desktop shortcuts + desktop polish

**Files:**
- Create: `<repo>/configs/desktop/hermes-terminal.desktop`, `<repo>/configs/desktop/hermes-setup.desktop`
- Modify: `<repo>/Dockerfile` (seed shortcuts into `/opt/hermes-defaults/Desktop`)
- Modify: `<repo>/entrypoint.sh` (place + trust the shortcuts; optional simple background)
- Create: `<repo>/scripts/verify-desktop-shortcuts.sh`

**Interfaces:**
- Consumes: the seeded home (2A) + working desktop.
- Produces: trusted launchers on the XFCE desktop for `hermes` (TUI) and `hermes setup`. (The "Hermes Dashboard" shortcut lands in 2C, when the dashboard auto-starts on 9119.)

- [ ] **Step 1: Write the failing test — `scripts/verify-desktop-shortcuts.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-shortcuts] both .desktop files present + executable on the Desktop?"
docker exec "$C" su - "$U" -c 'test -x ~/Desktop/hermes-terminal.desktop && test -x ~/Desktop/hermes-setup.desktop' \
  && echo "  OK present" || { echo "  FAIL missing"; exit 1; }
echo "[verify-shortcuts] marked trusted (no XFCE untrusted-app prompt)?"
docker exec "$C" su - "$U" -c 'gio info ~/Desktop/hermes-terminal.desktop 2>/dev/null | grep -q "metadata::trusted: true"' \
  && echo "  OK trusted" || { echo "  FAIL not trusted"; exit 1; }
echo "[verify-shortcuts] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-desktop-shortcuts.sh` → FAIL.

- [ ] **Step 3: Write the two `.desktop` files**

`configs/desktop/hermes-terminal.desktop`:
```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Hermes Terminal
Comment=Hermes TUI (computer_use enabled)
Exec=xfce4-terminal -e "bash -lc 'DISPLAY=:1 hermes; exec bash'"
Icon=utilities-terminal
Terminal=false
Categories=Utility;
```

`configs/desktop/hermes-setup.desktop`:
```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Hermes Setup
Comment=Hermes onboarding (model, channels, skills)
Exec=xfce4-terminal -e "bash -lc 'hermes setup; exec bash'"
Icon=preferences-system
Terminal=false
Categories=Utility;
```

- [ ] **Step 4: Bake into the template** (`Dockerfile`):

```dockerfile
COPY configs/desktop/hermes-terminal.desktop configs/desktop/hermes-setup.desktop /opt/hermes-defaults/Desktop/
```

- [ ] **Step 5: Place + trust in `entrypoint.sh`** — after the home seed (Task 2A) so the volume has them; mark trusted to suppress XFCE's prompt:

```bash
DESKTOP_DIR="/home/$USER/Desktop"
mkdir -p "$DESKTOP_DIR"
for s in hermes-terminal.desktop hermes-setup.desktop; do
  [ -f "$DESKTOP_DIR/$s" ] || cp "/opt/hermes-defaults/Desktop/$s" "$DESKTOP_DIR/$s" 2>/dev/null || true
done
for f in "$DESKTOP_DIR"/*.desktop; do
  [ -f "$f" ] || continue
  chmod +x "$f"
  su - "$USER" -c "dbus-launch gio set '$f' metadata::trusted true" 2>/dev/null || true
done
chown -R "$USER:$USER" "$DESKTOP_DIR"
```

- [ ] **Step 6: Rebuild + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-desktop-shortcuts.sh`
Expected: `[verify-shortcuts] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅`, and `./scripts/verify-persistence.sh` → PASS (shortcuts persist on the volume).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(2b): Hermes Terminal + Setup desktop shortcuts (trusted)"
```

---

## Phase 2C (deferred)

After 2B is reviewed: 2C auto-starts the web dashboard on **9119** (`--host 0.0.0.0` + basic-auth = desktop creds, host-map `127.0.0.1:9119`), adds the **Hermes Dashboard** desktop shortcut (→ `http://127.0.0.1:9119`), slims the image (multi-stage; drop `build-essential`/`python3-dev`/`pkg-config`/`libffi-dev` after install), pins Hermes to a release tag (replace `--branch main`), suppresses the cosmetic cua systemd-unit warning, fixes the inert `.bashrc` env append, adds `.env.example` + the README / Docker Hub overview, and sweeps the remaining deferred Minors. Multi-arch (arm64 → Chromium) is a later follow-on.

## Self-Review

- **Spec coverage (2B scope):** PID-1 init + dead-service detection (design "tini/s6"; 2A-review bare-bash-PID1 finding) → Task 1; RDP access (design Layer ①, Ports) → Task 2; RDP→`:1` convergence (design "The crux" — static convergence, fallback included) → Task 3; desktop shortcuts (design Layer ⑥) → Task 4. Dashboard/slimming/pin/README are explicitly 2C — deferred, not gaps. Wallpaper/locale folded into "polish" and kept minimal (fonts already present from the spike).
- **Placeholder scan:** no "TBD"/"add error handling". Task 3's fallback is a concrete revert + a named doc + a SKIP convention, not hand-waving. The `.desktop`/xrdp/startwm contents are literal.
- **Type/name consistency:** container `hermes-desktop`; user `${HERMES_USER:-hermes}`/`$USER`; ports 6080/5901/3389; display `:1`; VNC backend `127.0.0.1:5901`; template `/opt/hermes-defaults` (+ `/Desktop`); xrdp session `[Hermes-:1]`; verify scripts `verify-init/rdp/rdp-converge/desktop-shortcuts`. Each new verify script is added before later tasks depend on the container state it checks.
- **Regression guard:** every task re-runs `verify-gonogo.sh` (computer_use) and the volume-touching tasks re-run `verify-persistence.sh`. xRDP starts as root daemons (separate from the `:1` session), so it cannot disturb the AT-SPI/cua path on `:1`.
- **Init choice flagged for the review gate:** tini (`init: true`) over s6 is a deliberate, reversible decision recorded in Architecture; if the reviewer/user prefers s6 supervision, Task 1 is where it changes.

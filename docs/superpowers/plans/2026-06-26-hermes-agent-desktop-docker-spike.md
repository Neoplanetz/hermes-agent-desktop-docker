> ⚠️ **HISTORICAL — pre-pivot.** This document predates the **2026-06-30 pivot** to a public image. It describes the original `computer_use` / **cua-driver** native desktop-input ambition (AT-SPI tree + XTest), which was **proven insecure under this VNC/container model and dropped** — native desktop input is now a documented **non-goal**. The shipped product is **secure, zero-privilege CDP browser automation** (Hermes `/browser` → CDP Chrome on loopback `127.0.0.1:9222`). Current truth: `docs/superpowers/specs/2026-06-30-public-cdp-scope-design.md`, the README “Known limitations,” and the repo itself.

# Hermes Agent Desktop Docker — Phase 1 (Validation Spike) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the load-bearing assumption — that Hermes' `computer_use` (cua-driver, AT-SPI tree + XTest input) and a visible CDP browser actually work against a **TigerVNC `Xvnc :1`** desktop inside Docker — by building a minimal image and running a concrete go/no-go verification battery.

**Architecture:** Scaffold the new `hermes-agent-desktop-docker` repo. Build a minimal Ubuntu 24.04 + XFCE4 image with TigerVNC `:1` + NoVNC, an AT-SPI accessibility bus, Hermes installed root-FHS, and cua-driver. Verification is shell/`docker exec`-based: each task ships a `scripts/verify-*.sh` that exits non-zero until its feature exists (our TDD "failing test"), then we implement the Dockerfile/entrypoint change, rebuild, and the script passes. The spike image is **grown into** the real product in Phase 2 — it is not throwaway.

**Tech Stack:** Docker (linux/amd64 for the spike), Ubuntu 24.04, XFCE4, TigerVNC, NoVNC/websockify, Hermes Agent (Python/uv, install.sh), cua-driver, AT-SPI (`at-spi2-core`), `xdotool` (XTest exerciser), `python3-gi` + `gir1.2-atspi-2.0` (AT-SPI probe), Google Chrome (CDP).

## Global Constraints

Copied verbatim from the spec — every task implicitly includes these:

- **Base OS:** Ubuntu 24.04. Desktop: XFCE4. (Spike is **linux/amd64 only**; arm64 deferred to Phase 2.)
- **Display:** the agent's canvas is **`:1`** (TigerVNC `Xvnc`), geometry `1920x1080`, depth `24`. NoVNC on `6080`, raw VNC on `5901`.
- **Hermes install:** via `install.sh`, **root-FHS** (automatic when build runs as root on Linux → `/usr/local/bin/hermes`, code `/usr/local/lib/hermes-agent`), **non-interactive**, setup skipped, branch pinned. Exact: `--non-interactive --skip-setup --branch main` (plus `--skip-browser --no-skills` to keep the spike lean).
- **Agent runs as an unprivileged user** (`hermes`, uid 1000), never root.
- **`computer_use` requires:** `DISPLAY=:1` + `XAUTHORITY` reachable, AT-SPI bus up, XTest on the X server. Mechanism: AT-SPI accessibility tree + synthesized XTest input.
- **No secrets baked.** The go/no-go gate must pass **without** any model API key (doctor + direct XTest/AT-SPI/CDP probes, not a model-driven action).
- **Repo location (default, user may redirect before execution):** new sibling repo at `/home/neoplanetz/Documents/github/hermes-agent-desktop-docker`. This plan document stays in the OpenClaw repo alongside the spec; the spike *code* lives in the new repo.

## Go/No-Go criterion (what this whole phase decides)

**GO** (proceed to Phase 2 with TigerVNC) iff all of these pass on `:1`:
1. `hermes computer-use doctor` exits 0.
2. XTest pointer injection lands (`xdotool mousemove` → `getmouselocation` echoes the coordinates).
3. AT-SPI tree is readable (a `python3 Atspi` probe lists ≥1 running app, e.g. the panel/terminal).
4. A visible Chrome on `:1` answers CDP on `:9222` (`curl http://127.0.0.1:9222/json/version` returns JSON).

**NO-GO fallback** (try before re-scoping): swap `:1` from TigerVNC `Xvnc` to **Xvfb + x11vnc** and re-run the battery. Record which backend wins in `SPIKE-RESULT.md`.

---

### Task 1: Scaffold repo + minimal XFCE desktop on `Xvnc :1` reachable via NoVNC

**Files:**
- Create: `<repo>/Dockerfile`
- Create: `<repo>/entrypoint.sh`
- Create: `<repo>/docker-compose.yml`
- Create: `<repo>/.dockerignore`
- Create: `<repo>/.gitignore`
- Create: `<repo>/scripts/spike-up.sh` (build + run helper)
- Create: `<repo>/scripts/verify-desktop.sh` (the test)
- Create: `<repo>/README.md` (one-line stub)

**Interfaces:**
- Produces: a running container named `hermes-spike` with `Xvnc :1` (1920x1080x24), NoVNC on host `6080`, raw VNC on host `5901`. Later tasks `docker exec hermes-spike …` and add steps to `entrypoint.sh`.

- [ ] **Step 1: Scaffold the new repo**

```bash
mkdir -p /home/neoplanetz/Documents/github/hermes-agent-desktop-docker/scripts
cd /home/neoplanetz/Documents/github/hermes-agent-desktop-docker
git init
printf 'node_modules/\n*.log\n.env\n' > .gitignore
printf '.git\nscripts/\n*.md\n' > .dockerignore
printf '# Hermes Agent Desktop Docker (spike)\n\nValidation spike — see ../openclaw-desktop-docker/docs/superpowers/plans/2026-06-26-hermes-agent-desktop-docker-spike.md\n' > README.md
```

- [ ] **Step 2: Write the failing test — `scripts/verify-desktop.sh`**

```bash
#!/usr/bin/env bash
# Passes when Xvnc :1 is up and NoVNC serves the web client.
set -euo pipefail
C=hermes-spike
echo "[verify-desktop] X display :1 present?"
docker exec "$C" bash -lc 'DISPLAY=:1 xdpyinfo >/dev/null' \
  && echo "  OK :1 reachable" || { echo "  FAIL :1"; exit 1; }
echo "[verify-desktop] NoVNC serving on 6080?"
curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null \
  && echo "  OK NoVNC" || { echo "  FAIL NoVNC"; exit 1; }
echo "[verify-desktop] VNC TCP 5901 open?"
docker exec "$C" bash -lc 'ss -ltn | grep -q ":5901"' \
  && echo "  OK 5901" || { echo "  FAIL 5901"; exit 1; }
echo "[verify-desktop] PASS"
```

```bash
chmod +x scripts/verify-desktop.sh scripts/spike-up.sh 2>/dev/null || true
```

- [ ] **Step 3: Write `scripts/spike-up.sh` (build + run helper)**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose build
docker compose up -d
echo "Waiting for services to settle…"
for i in $(seq 1 30); do
  if docker exec hermes-spike bash -lc 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'; then break; fi
  sleep 1
done
docker compose ps
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `./scripts/spike-up.sh` will fail (no Dockerfile yet). That is the expected failure for this step:

Run: `./scripts/verify-desktop.sh`
Expected: FAIL — container `hermes-spike` does not exist yet.

- [ ] **Step 5: Write `Dockerfile` (minimal desktop)**

```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    DISPLAY=:1 \
    VNC_RESOLUTION=1920x1080 \
    VNC_COL_DEPTH=24
RUN apt-get update && apt-get install -y --no-install-recommends \
      xfce4 xfce4-terminal dbus-x11 \
      tigervnc-standalone-server tigervnc-common tigervnc-tools \
      novnc websockify \
      sudo curl wget ca-certificates net-tools iproute2 lsof procps \
      x11-utils xauth \
      fonts-noto-cjk fonts-noto-color-emoji \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash -u 1000 hermes \
    && adduser hermes sudo \
    && echo 'hermes ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/hermes \
    && chmod 0440 /etc/sudoers.d/hermes
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 6080 5901
ENTRYPOINT ["/entrypoint.sh"]
```

- [ ] **Step 6: Write `entrypoint.sh` (start Xvnc :1 + NoVNC)**

```bash
#!/bin/bash
set -e
USER=hermes
PASSWORD=hermes123
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
VNC_COL_DEPTH="${VNC_COL_DEPTH:-24}"

# VNC password
mkdir -p /home/$USER/.vnc
echo "$PASSWORD" | vncpasswd -f > /home/$USER/.vnc/passwd
chmod 600 /home/$USER/.vnc/passwd
chown -R $USER:$USER /home/$USER/.vnc

# xstartup -> XFCE
cat > /home/$USER/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x /home/$USER/.vnc/xstartup
chown $USER:$USER /home/$USER/.vnc/xstartup

# clean stale + start Xvnc :1
su - "$USER" -c "vncserver -kill :1" 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
su - "$USER" -c "vncserver :1 -geometry ${VNC_RESOLUTION} -depth ${VNC_COL_DEPTH} \
  -localhost no -SecurityTypes VncAuth -passwd /home/$USER/.vnc/passwd"
sleep 2

# NoVNC
websockify --web=/usr/share/novnc 6080 localhost:5901 &
WS=$!
echo "Spike desktop up: NoVNC http://localhost:6080/vnc.html  (vnc pw: $PASSWORD)"
wait $WS
```

- [ ] **Step 7: Write `docker-compose.yml`**

```yaml
services:
  hermes-spike:
    build: { context: ., dockerfile: Dockerfile }
    image: hermes-desktop-spike:latest
    container_name: hermes-spike
    ports:
      - "127.0.0.1:6080:6080"
      - "127.0.0.1:5901:5901"
    shm_size: "2gb"
    security_opt: [ "seccomp=unconfined" ]
    restart: unless-stopped
```

- [ ] **Step 8: Build, run, and verify it passes**

Run: `./scripts/spike-up.sh && ./scripts/verify-desktop.sh`
Expected: ends with `[verify-desktop] PASS`. (Also open `http://localhost:6080/vnc.html`, password `hermes123`, and confirm the XFCE desktop renders.)

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "spike: minimal XFCE desktop on Xvnc :1 via NoVNC"
```

---

### Task 2: AT-SPI accessibility bus running on `:1`

**Files:**
- Modify: `<repo>/Dockerfile` (apt: `at-spi2-core`, `python3-gi`, `gir1.2-atspi-2.0`, `mousepad`)
- Modify: `<repo>/entrypoint.sh` (export a11y env; nudge the a11y bus)
- Create: `<repo>/scripts/verify-atspi.sh` (the test)

**Interfaces:**
- Consumes: running `hermes-spike` with `:1` from Task 1.
- Produces: `org.a11y.Bus` resolvable on the session bus under `:1`, and a Python `Atspi` probe that lists running apps. Task 4/5 rely on this for `computer_use`.

- [ ] **Step 1: Write the failing test — `scripts/verify-atspi.sh`**

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/verify-atspi.sh`
Expected: FAIL — `at-spi2-core`/`python3-gi` not installed yet, or a11y bus not up.

- [ ] **Step 3: Add packages to the Dockerfile apt list**

Modify the apt block in `Dockerfile` to also install (append to the existing `apt-get install` line):

```dockerfile
      at-spi2-core gir1.2-atspi-2.0 python3-gi \
      mousepad xdotool \
```

- [ ] **Step 4: Enable accessibility in `entrypoint.sh`**

Insert before the `vncserver :1` start, so the a11y env is present for the session, and write it into the user's xprofile so XFCE-launched apps inherit it:

```bash
# AT-SPI / accessibility for computer_use
cat > /home/$USER/.xprofile <<'EOF'
export GTK_MODULES=gail:atk-bridge
export QT_ACCESSIBILITY=1
export NO_AT_BRIDGE=0
export OOO_FORCE_DESKTOP=gnome
EOF
chown $USER:$USER /home/$USER/.xprofile
# Turn on toolkit accessibility (dbus-activated a11y bus needs this hint)
su - "$USER" -c "DISPLAY=:1 xfconf-query -c xsettings -p /Net/EnableAccessibility -n -t int -s 1" 2>/dev/null || true
```

> Note for the implementer: the `org.a11y.Bus` daemon is **dbus-activated** — installing `at-spi2-core` and having a session dbus (XFCE's `dbus-launch`) is usually enough; the first client request (`dbus-send … GetAddress` or `Atspi.init()`) starts `at-spi-bus-launcher`. If `verify-atspi` still fails, explicitly launch it in `.xprofile`: `/usr/libexec/at-spi-bus-launcher --launch-immediately &`.

- [ ] **Step 5: Rebuild, run, verify it passes**

Run: `./scripts/spike-up.sh && ./scripts/verify-atspi.sh`
Expected: ends with `[verify-atspi] PASS` and prints e.g. `apps: 3 ['xfce4-panel', 'mousepad', 'xfdesktop']`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "spike: AT-SPI accessibility bus + tree readable on :1"
```

---

### Task 3: Install Hermes Agent (root-FHS, pinned, non-interactive)

**Files:**
- Modify: `<repo>/Dockerfile` (install.sh; `ripgrep`, `ffmpeg`, `git`)
- Create: `<repo>/scripts/verify-hermes.sh` (the test)

**Interfaces:**
- Consumes: base image from Task 2.
- Produces: `/usr/local/bin/hermes` on PATH for all users; `hermes --version` works. Task 4 calls `hermes computer-use …`.

- [ ] **Step 1: Write the failing test — `scripts/verify-hermes.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
C=hermes-spike
echo "[verify-hermes] hermes on PATH at /usr/local/bin?"
docker exec "$C" su - hermes -c 'command -v hermes' | grep -q '/usr/local/bin/hermes' \
  && echo "  OK path" || { echo "  FAIL path"; exit 1; }
echo "[verify-hermes] hermes --version runs?"
docker exec "$C" su - hermes -c 'hermes --version' \
  && echo "  OK version" || { echo "  FAIL version"; exit 1; }
echo "[verify-hermes] PASS"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/verify-hermes.sh`
Expected: FAIL — `hermes` not installed.

- [ ] **Step 3: Add Hermes install to the Dockerfile**

Append after the user-creation block (runs as root → automatic FHS layout). Add `git`, `ripgrep`, `ffmpeg` first (installer would otherwise prompt for the latter two, which `--non-interactive` declines):

```dockerfile
# Hermes runtime deps (installer declines these under --non-interactive)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ripgrep ffmpeg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hermes Agent — root FHS install (/usr/local/bin/hermes), pinned, non-interactive.
ARG HERMES_BRANCH=main
ENV HERMES_HOME=/root/.hermes
RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
      --non-interactive --skip-setup --skip-browser --no-skills \
      --branch "${HERMES_BRANCH}" \
    && /usr/local/bin/hermes --version
```

> Implementer note: `--skip-browser` omits Hermes' Playwright Chromium to keep the spike lean — the CDP test in Task 5 uses system Google Chrome instead. If `install.sh` exits non-zero, read its tail output; the most likely cause is a missing build tool — add it to the apt line above rather than working around it.

- [ ] **Step 4: Rebuild, run, verify it passes**

Run: `./scripts/spike-up.sh && ./scripts/verify-hermes.sh`
Expected: ends with `[verify-hermes] PASS` and prints a Hermes version (e.g. `0.17.x`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "spike: install Hermes Agent (root-FHS, pinned, non-interactive)"
```

---

### Task 4: cua-driver + `computer_use` wired to `:1`; doctor passes

**Files:**
- Modify: `<repo>/entrypoint.sh` (per-user `computer-use install` on first boot; export `DISPLAY`/`XAUTHORITY`; seed minimal `~/.hermes/config.yaml`)
- Create: `<repo>/scripts/verify-doctor.sh` (the test)

**Interfaces:**
- Consumes: `hermes` from Task 3; AT-SPI from Task 2.
- Produces: `hermes computer-use doctor` exits 0 for user `hermes` with `DISPLAY=:1`. Task 5 exercises actual input.

- [ ] **Step 1: Write the failing test — `scripts/verify-doctor.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
C=hermes-spike
echo "[verify-doctor] hermes computer-use doctor (DISPLAY=:1)…"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor'
echo "[verify-doctor] exit 0 → PASS"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/verify-doctor.sh`
Expected: FAIL — cua-driver not installed; doctor reports missing driver (or `computer-use` subcommand unavailable until installed).

- [ ] **Step 3: Wire computer_use in `entrypoint.sh`**

Add near the end, before the final `wait`, after `:1` is up. Runs as the unprivileged user (cua-driver may install per-user state into `~/.hermes`; doing it at first boot is volume-safe). Idempotent via a marker:

```bash
# Ensure ~/.hermes + minimal config exist and DISPLAY is wired for the agent
su - "$USER" -c 'mkdir -p ~/.hermes'
if [ ! -f /home/$USER/.hermes/config.yaml ]; then
  su - "$USER" -c 'cat > ~/.hermes/config.yaml <<YAML
computer_use:
  cua_telemetry: false
YAML'
fi
# Persist DISPLAY/XAUTHORITY for every login shell the agent uses
grep -q 'HERMES SPIKE DISPLAY' /home/$USER/.bashrc 2>/dev/null || \
  printf '\n# HERMES SPIKE DISPLAY\nexport DISPLAY=:1\nexport XAUTHORITY=/home/%s/.Xauthority\n' "$USER" \
  >> /home/$USER/.bashrc
chown -R $USER:$USER /home/$USER/.hermes /home/$USER/.bashrc

# Install cua-driver once (needs network on first boot)
if [ ! -f /home/$USER/.hermes/.cua-installed ]; then
  if su - "$USER" -c 'DISPLAY=:1 hermes computer-use install'; then
    su - "$USER" -c 'touch ~/.hermes/.cua-installed'
  else
    echo "WARN: hermes computer-use install failed (see logs)"
  fi
fi
```

- [ ] **Step 4: Rebuild, run, verify it passes**

Run: `./scripts/spike-up.sh && ./scripts/verify-doctor.sh`
Expected: doctor exits 0. Read its checklist output — it should report the display reachable, AT-SPI present, and input backend (XTest) available. **If doctor flags a specific missing piece** (e.g. an input lib), add the package to the Dockerfile apt line and rebuild — that is the spike's real work.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "spike: cua-driver + computer_use wired to :1, doctor passes"
```

---

### Task 5: Go/No-Go battery — XTest + AT-SPI action + visible CDP browser; record result

**Files:**
- Modify: `<repo>/Dockerfile` (Google Chrome + `--no-sandbox` wrapper)
- Create: `<repo>/scripts/verify-gonogo.sh` (the combined gate)
- Create: `<repo>/SPIKE-RESULT.md` (the documented outcome)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: a single pass/fail gate + a written verdict that Phase 2 keys off.

- [ ] **Step 1: Add Google Chrome (amd64) with `--no-sandbox` wrapper to the Dockerfile**

```dockerfile
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && (apt-get update && apt-get install -y /tmp/chrome.deb || (apt-get -f install -y && apt-get install -y /tmp/chrome.deb)) \
    && rm -f /tmp/chrome.deb \
    && mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable-real \
    && printf '#!/bin/bash\nexec /usr/bin/google-chrome-stable-real --no-sandbox "$@"\n' > /usr/bin/google-chrome-stable \
    && chmod +x /usr/bin/google-chrome-stable \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Write the combined gate — `scripts/verify-gonogo.sh`**

```bash
#!/usr/bin/env bash
# The Phase 1 go/no-go gate. All four checks must pass.
set -euo pipefail
C=hermes-spike
fail() { echo "  FAIL: $1"; exit 1; }

echo "[1/4] hermes computer-use doctor"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null || fail "doctor"
echo "  OK"

echo "[2/4] XTest pointer injection on :1"
docker exec "$C" su - hermes -c 'DISPLAY=:1 xdotool mousemove 640 400'
LOC=$(docker exec "$C" su - hermes -c 'DISPLAY=:1 xdotool getmouselocation --shell')
echo "$LOC" | grep -q '^X=640$' && echo "$LOC" | grep -q '^Y=400$' || fail "XTest move ($LOC)"
echo "  OK"

echo "[3/4] AT-SPI tree readable"
docker exec "$C" su - hermes -c 'DISPLAY=:1 python3 - <<PY
import gi; gi.require_version("Atspi","2.0")
from gi.repository import Atspi
Atspi.init()
assert Atspi.get_desktop(0).get_child_count() >= 1
print("ok")
PY' >/dev/null || fail "AT-SPI tree"
echo "  OK"

echo "[4/4] visible Chrome on :1 answering CDP :9222"
docker exec "$C" su - hermes -c \
  'DISPLAY=:1 setsid google-chrome-stable --remote-debugging-port=9222 \
   --user-data-dir=/tmp/cdp-profile about:blank >/dev/null 2>&1 &' || true
sleep 4
docker exec "$C" bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null' || fail "CDP :9222"
echo "  OK"

echo "GO ✅ — all four checks passed"
```

- [ ] **Step 3: Rebuild, run the gate**

Run: `./scripts/spike-up.sh && ./scripts/verify-gonogo.sh`
Expected (GO): ends with `GO ✅ — all four checks passed`.
Also confirm visually over NoVNC: the Chrome window is visible on `:1` and the mouse jumped to ~(640,400).

- [ ] **Step 4: If NO-GO, try the Xvfb + x11vnc fallback**

Only if Step 3 fails on checks 1–3 (display/XTest/AT-SPI). Swap the `:1` backend: replace the `tigervnc-*` packages with `xvfb x11vnc`, and replace the `vncserver :1 …` line in `entrypoint.sh` with:

```bash
Xvfb :1 -screen 0 ${VNC_RESOLUTION}x${VNC_COL_DEPTH} &
sleep 1
su - "$USER" -c "DISPLAY=:1 setsid startxfce4 >/dev/null 2>&1 &"
sleep 2
x11vnc -display :1 -rfbport 5901 -forever -shared -nopw -bg
```

Rebuild and re-run `./scripts/verify-gonogo.sh`. Record which backend passed.

- [ ] **Step 5: Write `SPIKE-RESULT.md` and commit**

```bash
# Fill in actual outputs (doctor checklist, xdotool location, AT-SPI app list, CDP version JSON)
# and the verdict: GO (TigerVNC) | GO (Xvfb+x11vnc) | NO-GO (+ reason)
git add -A
git commit -m "spike: go/no-go battery + recorded SPIKE-RESULT verdict"
```

---

## Phase 2 (deferred until the spike verdict)

The full-image plan — porting the complete OpenClaw desktop shell, the auto-start `hermes dashboard` on `9119` with basic-auth, the `:1` convergence for RDP (xRDP→libvnc), desktop shortcuts, removal of the OpenClaw-specific machinery, and multi-arch — is written as a **separate plan after `SPIKE-RESULT.md` records the verdict**, because the winning display backend (TigerVNC vs Xvfb+x11vnc) changes those tasks. Do not pre-write Phase 2 against the unproven assumption.

## Self-Review

- **Spec coverage (Phase 1 scope):** validation milestone §"Validation milestone" → Tasks 1–5; go/no-go criterion → Task 5 gate + `SPIKE-RESULT.md`; root-FHS install (§Hermes facts / decisions) → Task 3; AT-SPI/XTest/`:1` (§The crux) → Tasks 2,4,5; Xvfb fallback (§Validation milestone) → Task 5 Step 4; new-repo decision (§Decisions #5) → Task 1. Phase-2-only spec items (dashboard 9119, RDP convergence, removals, multi-arch) are explicitly deferred above — not gaps.
- **Placeholder scan:** no "TBD"/"add error handling"/"similar to Task N"; every code step is literal. The two "implementer notes" are concrete fallback commands, not hand-waving.
- **Type/name consistency:** container `hermes-spike`, image `hermes-desktop-spike:latest`, user `hermes`, display `:1`, ports `6080/5901/9222`, binary `/usr/local/bin/hermes`, marker `~/.hermes/.cua-installed` — used identically across all tasks and verify scripts.

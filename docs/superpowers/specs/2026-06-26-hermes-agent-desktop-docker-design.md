> ⚠️ **HISTORICAL — pre-pivot.** This document predates the **2026-06-30 pivot** to a public image. It describes the original `computer_use` / **cua-driver** native desktop-input ambition (AT-SPI tree + XTest), which was **proven insecure under this VNC/container model and dropped** — native desktop input is now a documented **non-goal**. The shipped product is **secure, zero-privilege CDP browser automation** (Hermes `/browser` → CDP Chrome on loopback `127.0.0.1:9222`). Current truth: `docs/superpowers/specs/2026-06-30-public-cdp-scope-design.md`, the README “Known limitations,” and the repo itself.

# Design: Hermes Agent Desktop Docker

**Date:** 2026-06-26
**Status:** Approved for planning
**Author:** Brainstorming session (OpenClaw Desktop Docker → Hermes Agent port)

## Background

This repository ships **OpenClaw Desktop Docker** — a turnkey Ubuntu 24.04 + XFCE4 GUI
desktop (NoVNC / RDP / VNC) with OpenClaw pre-installed. It exists for two reasons:

1. OpenClaw's own Docker support was weak, so we containerized it ourselves.
2. To act as an assistant, OpenClaw needs to **operate a real computer** — drive a
   visible browser (CDP) and a GUI — which requires a real X display, a window
   manager, and a watchable desktop.

We now want the equivalent for **Hermes Agent** (Nous Research,
`github.com/nousresearch/hermes-agent`, MIT, v0.17.x). Hermes is effectively the
**successor/rebrand of OpenClaw** — it even ships `hermes claw migrate` to import
OpenClaw personas, memories, skills, and API keys, and its CLI verbs
(`hermes setup/model/tools/gateway/doctor`) mirror OpenClaw almost 1:1.

Re-evaluating the two reasons above against Hermes:

| OpenClaw reason | Status for Hermes |
|---|---|
| ① weak Docker support | **Gone** — Hermes has an official headless image (`nousresearch/hermes-agent`, debian13 + s6-overlay). |
| ② agent must operate a computer/browser | **Stronger** — Hermes' `computer_use` toolset is *designed* for a Linux X11 desktop with AT-SPI + a window manager, exactly what XFCE+VNC provides; plus visible local browser automation over CDP. |

**Conclusion that frames this design:** a desktop image is *only* worth building for the
computer-control use case. Headless use (TUI, dashboard, messaging gateway, cloud
browser) is already served by the official image. Therefore this product is scoped
deliberately around **letting Hermes operate a GUI desktop + visible browser,
observed and steered remotely.**

## Hermes facts that drive the design

Captured here because they were non-obvious and several upstream README statements
undersell them (verified against the official docs, not the README):

- **Runtime:** Python 3.11+ via `uv` (Astral), with Node.js 22 bundled. Installed by
  `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`.
  - Non-root install → `~/.local/bin/hermes`, code cloned to `~/.hermes/hermes-agent`.
  - **Root FHS install → `/usr/local/bin/hermes`, code at `/usr/local/lib/hermes-agent`.**
  - Optional system deps: `ripgrep`, `ffmpeg`, `git`.
- **Config / state:** `~/.hermes/` — `.env`, `config.yaml`, `SOUL.md`, `MEMORY.md`,
  `USER.md`, `AGENTS.md`, `cron/`, `sessions/`, `logs/`, `skills/`.
- **Interfaces (human ↔ agent):**
  - TUI: `hermes` / `hermes --tui` (primary).
  - Web dashboard: `hermes dashboard` → default `http://127.0.0.1:9119`, needs
    `[web,pty]` extras (FastAPI/Uvicorn + ptyprocess). Tabs: Status, **Chat (embeds
    the real TUI via pty + xterm.js)**, Config (form editor for `config.yaml`),
    API Keys, Sessions, Skills, MCP, Logs, Cron, Profiles, Channels, System.
    No auth when bound to loopback; **auth engages when bound to a non-loopback
    address** (basic-auth username/password, Nous Portal OAuth, or OIDC).
  - Messaging gateway: `hermes gateway run` — outbound to Telegram/Discord/Slack/
    WhatsApp/Signal/Email. The official image also exposes an OpenAI-compatible API +
    health endpoint on **8642**. Not needed for our default scope.
- **`computer_use` (the differentiator):**
  - Driver: official **cua-driver** (`trycua/cua`), spoken over MCP/stdio. **Linux is
    first-class.**
  - Requires: a reachable display server (`DISPLAY` for X11), **AT-SPI accessibility**
    (default-on for GNOME/KDE/XFCE), and a window manager. Headless servers need Xvfb;
    docs say **"VNC displays should work (Xvfb is compatible)"** but do not explicitly
    guarantee it.
  - Mechanism: reads the **AT-SPI accessibility tree** and injects **synthesized input
    via XTest** (X11) — it does *not* move the real cursor or steal focus.
  - Commands: `hermes computer-use install`, enable via `hermes -t computer_use chat`
    or `config.yaml` `computer_use:` block, diagnose via `hermes computer-use doctor`.
- **Browser automation:**
  - Local: `agent-browser` auto-launches a Chromium-family browser with
    `--remote-debugging-port=9222`; `/browser connect [ws://…]` attaches to an
    already-running **visible** browser via CDP (so a human can watch).
  - Cloud (optional): Browserbase / Browser Use / Firecrawl.
  - In containers Hermes auto-injects `--no-sandbox --disable-dev-shm-usage`;
    `AGENT_BROWSER_ARGS` overrides.
- **No delegation** to external agent CLIs (`claude`, `codex`) — unlike OpenClaw.
- **Prior art:** community Issue #15876 proposed almost exactly this (noVNC + desktop
  computer-use container). Closed, labeled P3, no maintainer adoption — i.e. an
  unfilled niche, and it predates the now-official cua-driver `computer_use`.

## Goal

A single `docker compose up -d` produces an Ubuntu 24.04 + XFCE4 desktop, reachable by
web browser (NoVNC), RDP, or VNC, with Hermes Agent pre-installed and pre-configured so
that:

1. The **web dashboard auto-starts on 9119** for setup and management (Config, API
   Keys, Skills, Channels) and for chatting via the embedded-TUI Chat tab.
2. A **terminal TUI** (`hermes`) is available in the desktop, with `computer_use`
   enabled.
3. **`computer_use` actually works against the desktop's X display**, and **a visible
   local browser** can be driven via CDP — both **observable and steerable** over
   NoVNC/RDP/VNC.

## Non-goals

- Running the messaging gateway (Telegram/Discord/…) or the 8642 API server by default.
  Users can start `hermes gateway run` after connecting a channel.
- Reproducing OpenClaw's dynamic VNC↔RDP display-sync machinery. We pin a single
  display instead (see Display design).
- Cloud-browser-only or headless operation — that is the official image's job, not this
  one's.
- A real systemd instance inside the container.
- Pinning Wayland support. We target X11 (`:1`) only.

## Architecture

**Chosen: A — extend our proven Ubuntu+XFCE desktop base; install Hermes root-FHS.**

The desktop/remote-access shell from OpenClaw Desktop Docker is agent-agnostic and
battle-tested; we keep it and swap the agent layer. Hermes installs to the FHS root
location so the immutable binary/code live in the image while per-user config persists
in the home volume.

Rejected alternatives:
- **B — base `FROM nousresearch/hermes-agent`** and layer XFCE+VNC on top. Their image
  is debian13 + s6-overlay as PID 1, which fights our entrypoint and desktop layer.
- **C — two containers** (headless Hermes + desktop) sharing an X display. `computer_use`
  needs the same host display; cross-container X sharing is brittle. Over-engineered.

### Why root-FHS install matters (volume-shadowing)

A named volume mounted at `/home/<user>` shadows anything baked into the home directory
at build time (the volume is empty on first run). OpenClaw sidesteps this by keeping
`openclaw` in `/usr/lib/node_modules` (image) and only config in `~/.openclaw` (volume).
We mirror that: `hermes` + code in `/usr/local` (image, immutable), `~/.hermes`
config/state in the home volume (persists). This also deletes the need for OpenClaw's
`/var/openclaw-npm` prefix gymnastics entirely.

### Layer design

| Layer | Content |
|---|---|
| **① Desktop shell (reused)** | Ubuntu 24.04 + XFCE4 + dbus; TigerVNC `:1`; NoVNC/websockify (6080); xRDP (3389); raw VNC (5901); CJK/emoji fonts, locale, TZ; user create / password sync / sudoers / VNC password; wallpaper; xstartup; xRDP `startwm`/`reconnectwm`. `shm_size: 2gb`, `seccomp=unconfined`, home volume. |
| **② Hermes runtime (new)** | `install.sh` run **non-interactively at build**, version pinned via `HERMES_VERSION` build arg, **root-FHS** target. Brings uv, Python 3.11+, bundled Node 22, plus apt `ripgrep` + `ffmpeg`. Install `[web,pty]` (or `[all]`) extras for the dashboard. Seed a default `~/.hermes/config.yaml` + `SOUL.md` from an `/opt/hermes-defaults` template on first boot if absent (model left unset). |
| **③ Computer Use (differentiator)** | Build-time `hermes computer-use install` (cua-driver). apt `at-spi2-core` + accessibility bus enabled in the XFCE session; `DISPLAY=:1` + `XAUTHORITY` exported to every hermes process; XTest available on Xvnc. `config.yaml` pre-enables `computer_use`. Entrypoint runs `hermes computer-use doctor` and logs the result. |
| **④ Browser (visible local)** | Keep Chrome (amd64) / Chromium (arm64) `--no-sandbox` wrapper. A helper/desktop-shortcut launches Chrome on `:1` with `--remote-debugging-port=9222` so `/browser connect` attaches to a browser the user can watch. `AGENT_BROWSER_ARGS=--no-sandbox`. |
| **⑤ entrypoint (simplified)** | validate USER/PASSWORD → create user / seed home template (incl. `~/.hermes` default if missing) → VNC password / dbus / **AT-SPI bus** / wallpaper / Xvnc `:1` / NoVNC / xRDP → export DISPLAY/XAUTHORITY → seed config → `hermes computer-use doctor` → **auto-start `hermes dashboard --host 0.0.0.0 --port 9119 --no-open`** under `setsid`. |
| **⑥ Desktop shortcuts** | "Hermes Dashboard" → `http://127.0.0.1:9119`; "Hermes Terminal" → `hermes`; "Hermes Setup" → `hermes setup`. |
| **Ports** | 6080 (NoVNC), 5901 (VNC), 3389 (RDP), **9119 (dashboard)**. `18789` removed. |

## The crux: making `computer_use` visible and reliable

`computer_use` operates on **one X display**. RDP normally spawns a *separate* X session
— the very reason OpenClaw built `openclaw-sync-display`. We do **not** rebuild that
dynamic machinery. Instead:

- **The agent is pinned to `:1`.** NoVNC and raw VNC already render `:1`.
- **xRDP is configured to attach to `:1` via a libvnc passthrough** (xRDP's `libvnc`
  backend → `localhost:5901`), so web / VNC / RDP all converge on the same desktop and
  the agent's actions are visible regardless of access method. This is *simpler* than
  OpenClaw's dynamic sync — it is static convergence on `:1`.
- **Fallback** (if xRDP→libvnc proves fiddly): RDP stays a separate general-use session,
  and we document that computer-use is observed via NoVNC/VNC. The agent still pins `:1`.

This single-display pinning is the *only* piece of OpenClaw's display-targeting concern
that survives — and only in static form.

## Removed from OpenClaw (confirmed unnecessary)

| Removed | Why |
|---|---|
| `/var/openclaw-npm` global-prefix machinery | npm-shadowing workaround; uv/install.sh + root-FHS replace it. |
| `openclaw` group + plugin-dir EACCES fix | OpenClaw npm-plugin-dir specific. |
| `systemctl-shim` | Hermes is container-native; the official image runs without systemd. (Verify no hard `systemctl` dependency during the spike.) |
| `openclaw-pair-latest` + device-pairing / scope-upgrade flow | Loopback dashboard needs no device pairing. |
| `openclaw-update` wrapper | No pairing to chase; update is `install.sh` re-run / `hermes` self-update. |
| `allowedOrigins` JSON migration | `openclaw.json` security-audit specific. |
| awk gateway-port JSON parser + `.bashrc` gateway hook | `openclaw.json` specific. |
| bonjour/mDNS disable | OpenClaw-plugin specific. |
| `xdg-open` internal-IP→127.0.0.1 rewrite hack | Hermes dashboard already targets `127.0.0.1`. |
| Gateway auth-token generation/validation/persist + profile.d hook | Replaced by optional dashboard basic-auth. |
| `claude` + `codex` CLIs | Hermes does not delegate to them. |
| `OPENCLAW_BROWSER_ENABLED` + `browser.*` CDP config block | Replaced by Hermes browser config + CDP `:9222` helper. |

## New build additions

`uv` (or via install.sh), `ripgrep`, `ffmpeg`, `at-spi2-core`, cua-driver
(`hermes computer-use install`), Hermes `[web,pty]` extras.

## Decisions locked (approved)

1. **Display:** converge all access paths on `:1`; xRDP→libvnc passthrough, with the
   "RDP separate + observe via NoVNC/VNC" fallback.
2. **Dashboard exposure:** bind `--host 0.0.0.0` **with basic-auth** (default
   credentials: username = the desktop user, password = the desktop password),
   host-map `127.0.0.1:9119:9119` only. In-desktop access (from the desktop's own
   Chrome) always works. LAN exposure is an opt-in compose block, mirroring OpenClaw's
   pattern.
3. **`claude`/`codex` CLIs:** removed (re-addable on request for the user's own use).
4. **Model/provider:** left unset; configured at runtime in the dashboard's API Keys
   tab. Nous Portal (single subscription: models + search + image + TTS + cloud browser)
   is the recommended path in docs.
5. **Project location:** a new repo `hermes-agent-desktop-docker` (separate product /
   Docker Hub image). This design doc is written here for now; the new repo is
   scaffolded at implementation time.

## Validation milestone (first implementation step)

Before porting the full image, build a **minimal** image (Ubuntu+XFCE+TigerVNC `:1` +
AT-SPI + Hermes + cua-driver) and verify the load-bearing assumption:

1. Connect via NoVNC, open a terminal.
2. `hermes computer-use doctor` → passes (display reachable, AT-SPI up, XTest works).
3. Smoke test: have `computer_use` click/type in an XFCE app and in a visible Chrome on
   `:1`; confirm actions land and are visible over NoVNC.
4. Confirm `/browser connect` attaches to the `:9222` Chrome.

**Go/No-Go:** if XTest+AT-SPI on `Xvnc :1` fails, the product's core value is at risk —
escalate before building the rest (consider Xvfb-backed `:1` + a separate VNC export, or
revisit scope). The fallback path (Xvfb + x11vnc instead of TigerVNC) is the first thing
to try.

## Open questions (for the planning pass)

1. **xRDP → libvnc passthrough to `:1`** — confirm the cleanest config (sesman `libvnc`
   module vs. alternatives) and whether it's worth shipping in v1 or deferring to the
   documented fallback.
2. **TigerVNC `Xvnc` XTEST support** — believed present; the spike confirms. If absent,
   switch `:1` to Xvfb + x11vnc.
3. **Dashboard auto-start under `--host 0.0.0.0`** — confirm `hermes dashboard` flags vs.
   the `HERMES_DASHBOARD=1 … gateway run` supervised path; pick the lighter one that
   doesn't pull in the 8642 API server.
4. **Version pinning** — does `install.sh` accept a version/ref pin, or do we
   `git checkout <tag>` + `uv sync` against `~/.hermes/hermes-agent` (or the FHS code
   dir) for reproducible builds?
5. **`computer-use install` at build time vs first boot** — baking is preferred; confirm
   cua-driver has no per-user runtime state that the home volume would shadow.

## Out of scope

- Wayland computer-use.
- Multi-profile / multi-user concurrent desktops.
- Official-image parity (s6 supervision, 8642 API, PUID/PGID remap) — adopt later only
  if needed.
- Automated UI testing of the dashboard.

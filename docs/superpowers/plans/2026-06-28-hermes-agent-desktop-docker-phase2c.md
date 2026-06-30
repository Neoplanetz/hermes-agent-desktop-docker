> ⚠️ **HISTORICAL — pre-pivot.** This document predates the **2026-06-30 pivot** to a public image. It describes the original `computer_use` / **cua-driver** native desktop-input ambition (AT-SPI tree + XTest), which was **proven insecure under this VNC/container model and dropped** — native desktop input is now a documented **non-goal**. The shipped product is **secure, zero-privilege CDP browser automation** (Hermes `/browser` → CDP Chrome on loopback `127.0.0.1:9222`). Current truth: `docs/superpowers/specs/2026-06-30-public-cdp-scope-design.md`, the README “Known limitations,” and the repo itself.

# Hermes Agent Desktop Docker — Phase 2C: Dashboard, Slimming & Publish-Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the product on top of the 2B remote-desktop shell — auto-start the Hermes web dashboard on **9119** with basic-auth (so the user can set a model, API keys, channels, and chat without a terminal), pin Hermes to a reproducible commit, slim the image, silence the two cosmetic boot warnings, remove the inert `.bashrc` hack, and ship `.env.example` + README — bringing the image to publish-ready v1.

**Architecture:** Continue on the product repo `/home/neoplanetz/Documents/github/hermes-agent-desktop-docker` (`main`, at `387fecf`). The dashboard is the last load-bearing feature (design Goal #1, deferred through 2B). It runs as the desktop user under `setsid`, bound `--host 0.0.0.0` (so Docker's `127.0.0.1:9119:9119` host-map can reach it) with the **built-in `BasicAuthProvider`** configured from the desktop credentials via environment variables — no plaintext password at rest (a scrypt hash is computed at boot and written, mode 600, to a user-owned env file). The web UI is pre-built into the image so the runtime launch uses `--skip-build` (no npm at boot). Everything else is hardening/cleanup. Each task keeps the TDD-style cycle: write/extend a `scripts/verify-*.sh` → run/fail → implement → rebuild → pass → commit, and re-runs `verify-gonogo.sh` so the `computer_use` stack never regresses.

**Tech Stack:** Docker (linux/amd64), Ubuntu 24.04, XFCE4, TigerVNC `Xvnc :1`, NoVNC, xRDP + libvnc, Docker init (tini), Hermes Agent v0.17.0 (root-FHS at `/usr/local/lib/hermes-agent`, venv at `…/venv`), bundled Node 22 (`/usr/local/bin/node`), cua-driver, FastAPI/Uvicorn dashboard.

## Global Constraints

- **Display `:1` is the single canvas.** NoVNC (6080), raw VNC (5901), and RDP (host `3390`→container `3389`, libvnc→`:1`) all converge on it. Do not spawn a second X session.
- **Do not regress 2A/2B.** After every task, `./scripts/verify-gonogo.sh` must still end `GO ✅`, and `verify-rdp.sh` / `verify-rdp-converge.sh` / `verify-desktop-shortcuts.sh` / `verify-persistence.sh` / `verify-identity.sh` / `verify-config-seed.sh` must still pass. `entrypoint.sh` keeps `set -euo pipefail`.
- **Identity/persistence unchanged:** session user `${HERMES_USER:-hermes}` (uid 1000), named `hermes-home` volume, first-boot seed from `/opt/hermes-defaults`. New home files seed through that same template/chown path.
- **Naming:** image/container `hermes-desktop`. Ports: 6080 (NoVNC), 5901 (VNC), 3389 (RDP, host-published `3390`), **9119 (dashboard, newly host-published `127.0.0.1:9119:9119`)**. `9222` stays EXPOSE-only (CDP).
- **No secrets baked** beyond the published dev default `hermes123`. The dashboard auth file holds only a **scrypt hash** + a random signing secret + the username (no reversible password); it is generated at runtime (mode 600, user-owned), never baked, never committed. Same model as the runtime-only VNC password in `/etc/xrdp/xrdp.ini`.
- **Hermes is pinned** (Task 1 onward): `--commit dd0e4ab81abccf7df5b11c6c16853d5e5de9db69` (== `hermes --version` `v0.17.0 (2026.6.19)`). Builds must reproduce this version.
- **Docker env:** logged OUT of Docker Hub (anonymous pulls of cached `ubuntu:24.04` work). Build/run via `./scripts/spike-up.sh`. Re-`docker login` ONLY before an image push (not in this plan). gh/Docker Hub account `Neoplanetz`.
- **Fresh-volume tasks:** the cua-install warning (Task 4) and the seed/append cleanups (Task 5) only manifest on a **fresh** `hermes-home` volume, because the entrypoint's first-boot guards (`.cua-installed`, `.seeded`) skip on a warm volume. Those tasks must verify after `docker compose down -v`.

---

### Task 1: Pin Hermes to a reproducible commit

**Files:**
- Modify: `<repo>/Dockerfile:32-38` (add `ARG HERMES_COMMIT`; pass `--commit`)
- Modify: `<repo>/scripts/verify-hermes.sh` (assert the pinned version string)

**Interfaces:**
- Consumes: the existing root-FHS install line (`install.sh … --branch "${HERMES_BRANCH}"`).
- Produces: a build that always installs Hermes `v0.17.0 (2026.6.19)` (checkout `dd0e4ab8…`), independent of where `main` has advanced. Later tasks rebuild against this exact version.

> **Why this is reproducible:** the upstream `install.sh` does `git clone --depth 1 --branch "$BRANCH"`, then for `--commit` runs `git cat-file -e <sha> || git fetch origin <sha>` followed by `git checkout --detach <sha>`. GitHub serves arbitrary commit SHAs to `git fetch`, so the depth-1 clone is topped up with the pinned object even after `main` moves. There is no `v0.17.x` git tag upstream (verified via `git ls-remote --tags`), so a commit pin is the correct mechanism.

- [ ] **Step 1: Extend `scripts/verify-hermes.sh` to assert the pinned version**

Add this check before the final `PASS` line (after the existing `hermes --version runs?` block):

```bash
echo "[verify-hermes] pinned to v0.17.0 (2026.6.19)?"
docker exec "$C" su - hermes -c 'hermes --version' | grep -q 'v0.17.0 (2026.6.19)' \
  && echo "  OK pinned version" || { echo "  FAIL version not pinned to v0.17.0 (2026.6.19)"; exit 1; }
echo "[verify-hermes] checkout pinned to dd0e4ab?"
docker exec "$C" git -C /usr/local/lib/hermes-agent rev-parse HEAD 2>/dev/null | grep -q '^dd0e4ab81abccf7df5b11c6c16853d5e5de9db69' \
  && echo "  OK pinned commit" || { echo "  FAIL checkout not at pinned commit"; exit 1; }
```

- [ ] **Step 2: Run to verify it fails (or is not-yet-asserted)**

Run: `./scripts/verify-hermes.sh`
Expected: the version grep currently PASSES by luck (the live image was built from `main` which is presently at `dd0e4ab`), so this step is a guard, not a red test. If it already passes, that confirms the assertion is correct; proceed to lock it with the explicit `--commit` so future rebuilds stay pinned.

- [ ] **Step 3: Pin the commit in the `Dockerfile`**

Replace the install block at `Dockerfile:32-38`:

```dockerfile
# Hermes Agent — root FHS install (/usr/local/bin/hermes), pinned, non-interactive.
ARG HERMES_BRANCH=main
ARG HERMES_COMMIT=dd0e4ab81abccf7df5b11c6c16853d5e5de9db69
ENV HERMES_HOME=/root/.hermes
RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
      --non-interactive --skip-setup --skip-browser --no-skills \
      --branch "${HERMES_BRANCH}" --commit "${HERMES_COMMIT}" \
    && /usr/local/bin/hermes --version
```

- [ ] **Step 4: Rebuild + verify**

Run: `./scripts/spike-up.sh && ./scripts/verify-hermes.sh`
Expected: `[verify-hermes] PASS` including `OK pinned version` and `OK pinned commit`. Then `./scripts/verify-gonogo.sh` → `GO ✅`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(2c): pin Hermes to commit dd0e4ab (v0.17.0) for reproducible builds"
```

---

### Task 2: Auto-start the web dashboard on 9119 with basic-auth

**Files:**
- Modify: `<repo>/Dockerfile` (pre-build the web UI; bake it into the image)
- Modify: `<repo>/entrypoint.sh` (compute scrypt hash → write user-owned auth env file → `setsid` launch the dashboard before the NoVNC `wait`)
- Modify: `<repo>/docker-compose.yml` (publish `127.0.0.1:9119:9119`; add 9119 to the healthcheck)
- Modify: `<repo>/Dockerfile` (`EXPOSE … 9119`)
- Create: `<repo>/scripts/verify-dashboard.sh`

**Interfaces:**
- Consumes: the pinned Hermes install (Task 1), the seeded `~/.hermes`, bundled Node (`/usr/local/bin/npm`), the venv python (`/usr/local/lib/hermes-agent/venv/bin/python`), and `$USER`/`$PASSWORD` (already validated at the top of `entrypoint.sh`).
- Produces: a dashboard process owned by `$USER`, listening on `0.0.0.0:9119`, gated by `BasicAuthProvider` (login = desktop user + desktop password). Task 3 adds its desktop shortcut.

> **Auth mechanism (verified against the installed source):** A non-loopback bind requires a registered auth provider or the gate fails closed. The built-in `plugins/dashboard_auth/basic` `BasicAuthProvider` (`supports_password = True`) reads, with env winning over `config.yaml`:
> `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`, `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH` (preferred — scrypt, no plaintext) or `…_PASSWORD` (plaintext fallback), `HERMES_DASHBOARD_BASIC_AUTH_SECRET` (optional token-signing key; without it sessions die on restart). We compute the scrypt hash at boot (password passed by env, never interpolated) via the module's own `hash_password()`, persist a random secret, and hand all three to the launch via a mode-600 user-owned env file. Login is a **form POST to `/auth/password-login`** (cookie session), NOT HTTP Basic — so the automated check asserts "auth engaged", and full login is a manual acceptance step.

- [ ] **Step 1: Write the failing test — `scripts/verify-dashboard.sh`**

```bash
#!/usr/bin/env bash
# Passes when the dashboard is listening on 9119 and is auth-gated (not open).
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-dashboard] port 9119 listening?"
docker exec "$C" bash -c 'ss -ltnH "sport = :9119" | grep -q .' \
  && echo "  OK 9119" || { echo "  FAIL 9119 not listening"; exit 1; }
echo "[verify-dashboard] a hermes dashboard process owns it?"
docker exec "$C" bash -lc 'pgrep -af "hermes dashboard" >/dev/null || pgrep -af "dashboard" | grep -q hermes' \
  && echo "  OK dashboard process" || { echo "  FAIL no dashboard process"; exit 1; }
echo "[verify-dashboard] auth engaged (root is gated, not the open app)?"
body=$(docker exec "$C" bash -lc 'curl -s -L --max-time 5 http://127.0.0.1:9119/' 2>/dev/null || true)
echo "$body" | grep -qiE 'login|password|sign in|authenticate' \
  && echo "  OK auth gate visible" || { echo "  FAIL dashboard not auth-gated"; exit 1; }
echo "[verify-dashboard] PASS (manual: open http://localhost:9119 → log in as $U / desktop password)"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-dashboard.sh` → FAIL (9119 not listening; the current entrypoint never starts the dashboard).

- [ ] **Step 3: Pre-build the web UI in the `Dockerfile`**

Add immediately AFTER the Hermes install block (after `Dockerfile:38`, before the Chrome block). Node/npm are on PATH from the install; the build is pure-JS (`tsc -b && vite build`) and needs no Python build deps:

```dockerfile
# Pre-build the dashboard web UI so the runtime launch can use --skip-build
# (no npm at boot). Output lands in web/dist under the immutable FHS lib dir.
RUN cd /usr/local/lib/hermes-agent/web \
    && npm run build \
    && test -d /usr/local/lib/hermes-agent/web/dist
```

- [ ] **Step 4: Add 9119 to `EXPOSE`** in the `Dockerfile` (replace the `EXPOSE` line near the end):

```dockerfile
EXPOSE 6080 5901 9222 3389 9119
```

- [ ] **Step 5: Launch the dashboard in `entrypoint.sh`**

Insert this block AFTER the cua-driver install block (after `entrypoint.sh:169`) and BEFORE the `# NoVNC` block (`entrypoint.sh:171`). It must run before the final `wait $WS`:

```bash
# ── Hermes web dashboard (9119, basic-auth = desktop credentials) ──
# Bind 0.0.0.0 so Docker's 127.0.0.1:9119:9119 host-map reaches it; a non-loopback
# bind forces an auth provider, so configure BasicAuthProvider from the desktop
# creds. No plaintext password at rest: compute a scrypt hash (password via env,
# never interpolated) and persist a random signing secret. The env file is
# user-owned, mode 600, and holds only the hash + secret + username.
DASH_DIR="/home/$USER/.hermes"
DASH_SECRET_FILE="$DASH_DIR/.dashboard-secret"
DASH_ENV_FILE="$DASH_DIR/dashboard.env"
su - "$USER" -c 'mkdir -p ~/.hermes/logs'
PW_HASH="$(HPW="$PASSWORD" PYTHONPATH=/usr/local/lib/hermes-agent \
  /usr/local/lib/hermes-agent/venv/bin/python -c \
  'import os; from plugins.dashboard_auth.basic import hash_password; print(hash_password(os.environ["HPW"]))')"
if [ ! -s "$DASH_SECRET_FILE" ]; then
  ( umask 077; /usr/local/lib/hermes-agent/venv/bin/python -c 'import secrets; print(secrets.token_hex(32))' > "$DASH_SECRET_FILE" )
fi
DASH_SECRET="$(cat "$DASH_SECRET_FILE")"
( umask 077
  {
    printf "HERMES_DASHBOARD_BASIC_AUTH_USERNAME='%s'\n" "$USER"
    printf "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH='%s'\n" "$PW_HASH"
    printf "HERMES_DASHBOARD_BASIC_AUTH_SECRET='%s'\n" "$DASH_SECRET"
  } > "$DASH_ENV_FILE"
)
chown -R "$USER:$USER" "$DASH_DIR"
# Launch detached as the user; source the auth env (single-quoted values, safe to source).
setsid su - "$USER" -c 'set -a; . ~/.hermes/dashboard.env; set +a; \
  exec hermes dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build' \
  >> "$DASH_DIR/logs/dashboard.boot.log" 2>&1 &
echo "Hermes dashboard starting on http://localhost:9119 (login: $USER / <desktop password>)"
```

> **Safety notes:** `$PASSWORD` already passed the entrypoint's no-newline/CR/colon validation. It is passed to Python only through the `HPW` env var (no shell or string interpolation). The scrypt hash and hex secret contain only `[A-Za-z0-9+/=$]` / `[0-9a-f]`; writing them single-quoted and sourcing with `set -a` round-trips them verbatim (no `$8`/`$1` re-expansion of the `scrypt$n$r$p$…` `$` separators).

- [ ] **Step 6: Publish 9119 + extend the healthcheck in `docker-compose.yml`**

Add to `ports` (under the existing RDP mapping):

```yaml
      # Dashboard: hermes dashboard binds 0.0.0.0:9119 inside the container
      # (basic-auth required on a non-loopback bind); published to host loopback only.
      - "127.0.0.1:9119:9119"
```

Replace the healthcheck `test` line to also require 9119 listening:

```yaml
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null && su - \"${HERMES_USER:-hermes}\" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && pgrep -x xrdp >/dev/null && pgrep -x xrdp-sesman >/dev/null && ss -ltnH 'sport = :9119' | grep -q ."]
```

- [ ] **Step 7: Rebuild on a fresh volume + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && sleep 8 && ./scripts/verify-dashboard.sh`
Expected: `[verify-dashboard] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅`.
**Manual acceptance (the real proof):** open `http://localhost:9119` in a host browser → you are prompted to log in → entering `hermes` / `hermes123` lands on the dashboard (Status/Config/API Keys/Chat tabs). From the desktop's own Chrome (NoVNC), `http://127.0.0.1:9119` works with the same login. If 9119 is not listening, check `docker exec hermes-desktop cat /home/hermes/.hermes/logs/dashboard.boot.log` — the most likely cause is `--skip-build` not finding `web/dist` (confirm Step 3's `test -d` passed at build).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(2c): auto-start web dashboard on 9119 with basic-auth (desktop creds, no plaintext at rest)"
```

---

### Task 3: "Hermes Dashboard" desktop shortcut

**Files:**
- Create: `<repo>/configs/desktop/hermes-dashboard.desktop`
- Modify: `<repo>/Dockerfile:54` (add the new shortcut to the template COPY)
- Modify: `<repo>/entrypoint.sh:49` (add it to the place+trust loop)
- Modify: `<repo>/scripts/verify-desktop-shortcuts.sh` (assert the third shortcut)

**Interfaces:**
- Consumes: the running dashboard (Task 2) + the existing trusted-shortcut machinery (2B).
- Produces: a trusted "Hermes Dashboard" launcher on the desktop that opens `http://127.0.0.1:9119` in the in-desktop Chrome.

- [ ] **Step 1: Extend `scripts/verify-desktop-shortcuts.sh`**

Replace the two assertion blocks so all THREE shortcuts are checked:

```bash
echo "[verify-shortcuts] all three .desktop files present + executable on the Desktop?"
docker exec "$C" su - "$U" -c 'test -x ~/Desktop/hermes-terminal.desktop && test -x ~/Desktop/hermes-setup.desktop && test -x ~/Desktop/hermes-dashboard.desktop' \
  && echo "  OK present" || { echo "  FAIL missing"; exit 1; }
echo "[verify-shortcuts] all three marked trusted (no XFCE untrusted-app prompt)?"
docker exec "$C" su - "$U" -c 'for s in hermes-terminal hermes-setup hermes-dashboard; do gio info ~/Desktop/$s.desktop 2>/dev/null | grep -q "metadata::trusted: true" || exit 1; done' \
  && echo "  OK all trusted" || { echo "  FAIL not trusted"; exit 1; }
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-desktop-shortcuts.sh` → FAIL (dashboard shortcut missing).

- [ ] **Step 3: Write `configs/desktop/hermes-dashboard.desktop`** (match the existing `.desktop` style; open the dashboard in the no-sandbox Chrome):

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Hermes Dashboard
Comment=Web dashboard — model, API keys, chat, channels (login with your desktop user/password)
Exec=google-chrome-stable http://127.0.0.1:9119
Icon=preferences-desktop-remote-desktop
Terminal=false
Categories=Utility;Network;
```

- [ ] **Step 4: Bake it into the template** — update the desktop COPY in the `Dockerfile` (currently `Dockerfile:54`):

```dockerfile
COPY configs/desktop/hermes-terminal.desktop configs/desktop/hermes-setup.desktop configs/desktop/hermes-dashboard.desktop /opt/hermes-defaults/Desktop/
```

- [ ] **Step 5: Add it to the place+trust loop in `entrypoint.sh`** — extend the `for s in …` list (currently `entrypoint.sh:49`):

```bash
for s in hermes-terminal.desktop hermes-setup.desktop hermes-dashboard.desktop; do
```

(The loop body is unchanged — it copies from the template, `chmod +x`, and `gio set metadata::trusted true` with the path passed as `$1`, injection-safe.)

- [ ] **Step 6: Rebuild on a fresh volume + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-desktop-shortcuts.sh`
Expected: `[verify-shortcuts] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅` and `./scripts/verify-persistence.sh` → PASS.
**Manual:** in NoVNC, double-click "Hermes Dashboard" → Chrome opens the dashboard login.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(2c): Hermes Dashboard desktop shortcut (trusted) → 127.0.0.1:9119"
```

---

### Task 4: Suppress the two cosmetic boot warnings (cua systemd-unit + gail)

**Files:**
- Modify: `<repo>/Dockerfile` (bake a no-op `systemctl` shim under `/opt/hermes-noop`)
- Modify: `<repo>/entrypoint.sh:164` (run `hermes computer-use install` with the shim on PATH)
- Modify: `<repo>/entrypoint.sh:82` (drop `gail` from `GTK_MODULES`)
- Create: `<repo>/scripts/verify-quiet-boot.sh`

**Interfaces:**
- Consumes: the first-boot cua install + the `.xprofile` a11y env.
- Produces: a clean first-boot log — no `cua-driver installing did not complete` and no `gail` GTK module warning — with `computer_use` still fully functional.

> **Root causes (verified):** (1) `/usr/bin/systemctl` exists (pulled in as a dependency) but there is no running systemd bus, so cua-driver's post-install `systemctl --user …` step fails and cua reports "did not complete" — cosmetic, since cua runs on-demand over MCP (doctor exits 0). A PATH-scoped no-op `systemctl` (exit 0) for the install invocation only lets that step "succeed" silently WITHOUT replacing the real `/usr/bin/systemctl` globally (keeping the design's "no systemctl-shim" stance for everything else). (2) `GTK_MODULES=gail:atk-bridge` loads the obsolete GTK2 `gail` module, which GTK3 logs as not-found; `atk-bridge` alone is what AT-SPI needs.

- [ ] **Step 1: Write the failing test — `scripts/verify-quiet-boot.sh`**

```bash
#!/usr/bin/env bash
# Passes when a FRESH-volume boot logs neither cosmetic warning and cua still works.
# Run AFTER a `docker compose down -v && ./scripts/spike-up.sh` so first-boot ran.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] no cua 'did not complete' warning in boot log?"
docker logs "$C" 2>&1 | grep -qiE 'cua-driver installing did not complete|did not complete' \
  && { echo "  FAIL cua systemd warning present"; exit 1; } || echo "  OK no cua warning"
echo "[verify-quiet-boot] no gail GTK module warning in the VNC session log?"
# xstartup/GTK output goes to ~/.vnc/*.log (the X session), not docker logs.
docker exec "$C" su - hermes -c 'cat ~/.vnc/*.log 2>/dev/null' | grep -qiE 'gail|Failed to load module .gail' \
  && { echo "  FAIL gail warning present"; exit 1; } || echo "  OK no gail warning"
echo "[verify-quiet-boot] computer_use still healthy (doctor exit 0)?"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null \
  && echo "  OK doctor" || { echo "  FAIL doctor"; exit 1; }
echo "[verify-quiet-boot] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-quiet-boot.sh` → FAIL on the cua and/or gail warning.

- [ ] **Step 3: Bake the no-op `systemctl` shim in the `Dockerfile`**

Add near the end (e.g. just before the `COPY entrypoint.sh` line):

```dockerfile
# No-op systemctl shim, used ONLY (via PATH prefix) for the cua-driver install
# step so its systemd-unit registration "succeeds" silently in this no-systemd
# container. Does NOT shadow the real /usr/bin/systemctl for anything else.
RUN mkdir -p /opt/hermes-noop \
    && printf '#!/bin/sh\nexit 0\n' > /opt/hermes-noop/systemctl \
    && chmod 0755 /opt/hermes-noop/systemctl
```

- [ ] **Step 4: Use the shim for the cua install in `entrypoint.sh`**

Change the install invocation (currently `entrypoint.sh:164`) to prepend the shim dir to PATH for that command only:

```bash
  if su - "$USER" -c 'PATH=/opt/hermes-noop:$PATH DISPLAY=:1 hermes computer-use install'; then
```

- [ ] **Step 5: Drop `gail` from `GTK_MODULES` in `entrypoint.sh`**

In the `.xprofile` heredoc (currently `entrypoint.sh:82`), change:

```bash
export GTK_MODULES=atk-bridge
```

- [ ] **Step 6: Rebuild on a fresh volume + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-quiet-boot.sh`
Expected: `[verify-quiet-boot] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅` (AT-SPI tree still readable proves dropping `gail` did not break accessibility).
**Fallback** (if the shim does not fully silence cua): keep the shim, and additionally document the residual line in the README as expected; flip `verify-quiet-boot.sh`'s cua check to a `SKIP:` with the doc reference (mirror the 2B `verify-rdp-converge` skip convention). Record which path shipped.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "fix(2c): silence cosmetic cua systemd + gail warnings (PATH-scoped no-op systemctl, atk-bridge only)"
```

---

### Task 5: Remove the inert `.bashrc` env append + sweep legacy `.profile`

**Files:**
- Modify: `<repo>/entrypoint.sh:156-160` (delete the `.bashrc` DISPLAY/XAUTHORITY append)
- Create: `<repo>/scripts/verify-env-clean.sh`

**Interfaces:**
- Consumes: the rootfs `/etc/profile.d/hermes-display.sh` (added in 2B), which already exports `DISPLAY`/`XAUTHORITY` for every login shell.
- Produces: a `.bashrc` with no Hermes append and no leftover volume-side `.profile` display hack, with the agent's `DISPLAY` still correct.

> **Why the append is inert:** `~/.bashrc` returns early for non-interactive shells (`case $- in *i*) ;; *) return ;; esac`), so the appended `export DISPLAY=:1` never runs under the agent's non-interactive `su - "$USER" -c …` login shells. `/etc/profile.d/hermes-display.sh` (sourced by every login shell via `/etc/profile`) already provides those exports — so the append is both redundant and dead, and it writes to the home volume (the anti-pattern 2B moved away from).

- [ ] **Step 1: Write the failing test — `scripts/verify-env-clean.sh`**

```bash
#!/usr/bin/env bash
# Passes when DISPLAY/XAUTHORITY are set for login shells WITHOUT a .bashrc append.
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-env-clean] DISPLAY/XAUTHORITY set for a non-interactive login shell?"
docker exec "$C" su - "$U" -c 'echo "D=$DISPLAY X=$XAUTHORITY"' | grep -q 'D=:1 X=/home/' \
  && echo "  OK display env via profile.d" || { echo "  FAIL display env missing"; exit 1; }
echo "[verify-env-clean] no HERMES DESKTOP DISPLAY block appended to ~/.bashrc?"
docker exec "$C" su - "$U" -c 'grep -q "HERMES DESKTOP DISPLAY" ~/.bashrc 2>/dev/null' \
  && { echo "  FAIL .bashrc still has the inert append"; exit 1; } || echo "  OK .bashrc clean"
echo "[verify-env-clean] no legacy DISPLAY/dbus hack in ~/.profile?"
docker exec "$C" su - "$U" -c 'grep -qiE "DISPLAY=:1|DBUS_SESSION_BUS_ADDRESS|metadata::trusted" ~/.profile 2>/dev/null' \
  && { echo "  FAIL legacy ~/.profile hack present"; exit 1; } || echo "  OK ~/.profile clean"
echo "[verify-env-clean] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-env-clean.sh` → FAIL (`.bashrc` has the append).

- [ ] **Step 3: Delete the inert append in `entrypoint.sh`**

Remove these lines (currently `entrypoint.sh:156-160`):

```bash
# Persist DISPLAY/XAUTHORITY for every login shell the agent uses
grep -q 'HERMES DESKTOP DISPLAY' /home/$USER/.bashrc 2>/dev/null || \
  printf '\n# HERMES DESKTOP DISPLAY\nexport DISPLAY=:1\nexport XAUTHORITY=/home/%s/.Xauthority\n' "$USER" \
  >> /home/$USER/.bashrc
chown "$USER:$USER" "/home/$USER/.bashrc"
```

> Leave the surrounding `~/.hermes` config-seed block intact. The `/etc/profile.d/hermes-display.sh` rootfs file (from 2B) continues to provide `DISPLAY`/`XAUTHORITY`.

- [ ] **Step 4: Sweep any legacy template `.profile` hack**

Confirm no display/dbus hack is baked into the seed template or `/etc/skel`:

```bash
grep -rniE 'DISPLAY=:1|DBUS_SESSION_BUS_ADDRESS|metadata::trusted' \
  Dockerfile entrypoint.sh configs/ 2>/dev/null | grep -i profile || echo "no template .profile hack"
```

If a `.profile` hack is found in `/opt/hermes-defaults` seeding, remove it. (Expected: none — 2B's Codex pass migrated trust to `/etc/profile.d`; this step is the confirmation the deferred Minor asked for.)

- [ ] **Step 5: Rebuild on a fresh volume + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-env-clean.sh`
Expected: `[verify-env-clean] PASS`. Then `./scripts/verify-gonogo.sh` → `GO ✅` (the agent's `DISPLAY=:1` still resolves, proving profile.d covers it). Also re-run `./scripts/verify-desktop-shortcuts.sh` → PASS (trust still works).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "fix(2c): drop inert .bashrc DISPLAY append (profile.d covers it); confirm no legacy .profile hack"
```

---

### Task 6: Slim the image (purge build deps + trim gvfs)

**Files:**
- Modify: `<repo>/Dockerfile` (fold the Python build deps into the install layer and purge them there; trim `gvfs`)
- Create: `<repo>/scripts/verify-slim.sh`

**Interfaces:**
- Consumes: everything built above (the install + web build now live in known layers).
- Produces: a final image with no leftover `build-essential`/`python3-dev`/`pkg-config`/`libffi-dev` and only the gvfs piece the desktop-trust path needs.

> **Decision flagged for the review gate:** the design/2B notes say "multi-stage". A true multi-stage rewrite is high-risk here because the Hermes install scatters artifacts across `/usr/local/lib/hermes-agent`, `/usr/local/bin/{hermes,node,npm}`, and `/root/.hermes` (node + uv-managed Python) — enumerating every `COPY --from` is brittle. This task instead does an **in-layer purge** (install build deps, run install + web build, then `apt-get purge` the build deps in the SAME `RUN` so the space is actually reclaimed), which yields the same final-image saving with far less risk. If the reviewer/user wants a full multi-stage split, this is the task to change. Either way the gates below must stay green.

- [ ] **Step 1: Write the failing test — `scripts/verify-slim.sh`**

```bash
#!/usr/bin/env bash
# Passes when build-only deps are absent from the final image and gvfs is trimmed.
set -euo pipefail
C=hermes-desktop
echo "[verify-slim] build-essential / dev headers purged?"
docker exec "$C" bash -c 'for p in build-essential python3-dev pkg-config libffi-dev; do dpkg -s "$p" >/dev/null 2>&1 && { echo "  present: $p"; exit 1; }; done' \
  && echo "  OK build deps absent" || { echo "  FAIL a build dep remains"; exit 1; }
echo "[verify-slim] gvfsd-metadata still present (desktop-trust needs it)?"
docker exec "$C" bash -c 'command -v gvfsd-metadata >/dev/null 2>&1 || ls /usr/libexec/gvfsd-metadata >/dev/null 2>&1' \
  && echo "  OK gvfs-daemons retained" || { echo "  FAIL gvfsd-metadata missing (trust would break)"; exit 1; }
echo "[verify-slim] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-slim.sh` → FAIL (build deps still installed).

- [ ] **Step 3: Fold build deps into the install layer and purge them**

In the `Dockerfile`, REMOVE `build-essential python3-dev pkg-config libffi-dev` from the standalone runtime-deps `RUN` (currently `Dockerfile:27-30`, leaving `git ripgrep ffmpeg`):

```dockerfile
# Hermes runtime deps (installer declines these under --non-interactive)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ripgrep ffmpeg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

Then make the Hermes install layer install the build deps, run the install + web build, and purge in one `RUN` (replaces Task 1's block + Task 2 Step 3's block — combine them):

```dockerfile
# Hermes Agent — root FHS install (/usr/local/bin/hermes), pinned, non-interactive.
# Build deps live ONLY in this layer: installed, used for the install + web build,
# then purged so they never reach the final image.
ARG HERMES_BRANCH=main
ARG HERMES_COMMIT=dd0e4ab81abccf7df5b11c6c16853d5e5de9db69
ENV HERMES_HOME=/root/.hermes
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential python3-dev pkg-config libffi-dev \
    && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
         --non-interactive --skip-setup --skip-browser --no-skills \
         --branch "${HERMES_BRANCH}" --commit "${HERMES_COMMIT}" \
    && /usr/local/bin/hermes --version \
    && cd /usr/local/lib/hermes-agent/web && npm run build \
    && test -d /usr/local/lib/hermes-agent/web/dist \
    && apt-get purge -y build-essential python3-dev pkg-config libffi-dev \
    && apt-get autoremove -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

> Delete the now-superseded standalone `npm run build` `RUN` added in Task 2 Step 3 (it is merged here). Keep `git ripgrep ffmpeg` in the earlier runtime-deps layer.

- [ ] **Step 4: Trim `gvfs`** — in the first apt block (`Dockerfile:17`), drop the broad `gvfs` package but KEEP `gvfs-daemons` (provides `gvfsd-metadata`, which `gio set metadata::trusted` needs):

```dockerfile
      libglib2.0-bin gvfs-daemons \
```

- [ ] **Step 5: Rebuild on a fresh volume + verify (size + no regressions)**

```bash
docker compose down -v
docker image rm hermes-desktop:latest 2>/dev/null || true
./scripts/spike-up.sh
docker images hermes-desktop:latest --format 'size: {{.Size}}'
./scripts/verify-slim.sh
```

Expected: `[verify-slim] PASS` and a smaller image than the pre-slim baseline (the live baseline is ~6.38 GB virtual / 1.72 GB unique; expect a meaningful drop from purging the toolchain). Then the FULL regression set must stay green:

```bash
./scripts/verify-gonogo.sh && ./scripts/verify-dashboard.sh && ./scripts/verify-desktop-shortcuts.sh \
  && ./scripts/verify-quiet-boot.sh && ./scripts/verify-env-clean.sh \
  && ./scripts/verify-rdp.sh && ./scripts/verify-rdp-converge.sh \
  && ./scripts/verify-persistence.sh && ./scripts/verify-identity.sh && ./scripts/verify-config-seed.sh
```

Expected: all PASS / `GO ✅`. (Desktop-trust passing confirms `gvfs-daemons` is sufficient and dropping `gvfs` did not break `gio`.)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "perf(2c): slim image — purge Python build toolchain in-layer, trim gvfs to gvfs-daemons"
```

---

### Task 7: `.env.example`, README, and Docker Hub overview

**Files:**
- Create: `<repo>/.env.example`
- Rewrite: `<repo>/README.md` (currently a 2-line spike stub)
- Create: `<repo>/DOCKERHUB_OVERVIEW.md`
- Create: `<repo>/scripts/verify-docs.sh`

**Interfaces:**
- Consumes: the finished access model (NoVNC/VNC/RDP/dashboard) + credentials model.
- Produces: a user can clone, `cp .env.example .env`, edit, `docker compose up -d`, and reach every surface.

- [ ] **Step 1: Write the failing test — `scripts/verify-docs.sh`**

```bash
#!/usr/bin/env bash
# Passes when the publish-readiness docs exist and cover every access surface.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[verify-docs] .env.example exists with both vars?"
grep -q '^HERMES_USER=' .env.example && grep -q '^HERMES_PASSWORD=' .env.example \
  && echo "  OK .env.example" || { echo "  FAIL .env.example"; exit 1; }
echo "[verify-docs] README covers all four surfaces + default creds?"
for needle in '6080' '5901' '3390' '9119' 'hermes123'; do
  grep -q "$needle" README.md || { echo "  FAIL README missing: $needle"; exit 1; }
done
echo "  OK README"
echo "[verify-docs] DOCKERHUB_OVERVIEW present?"
test -s DOCKERHUB_OVERVIEW.md && echo "  OK overview" || { echo "  FAIL overview"; exit 1; }
echo "[verify-docs] PASS"
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/verify-docs.sh` → FAIL.

- [ ] **Step 3: Write `.env.example`**

```bash
# Hermes Agent Desktop — copy to .env and edit before `docker compose up -d`.
# These set the single desktop account AND the login for VNC/RDP and the
# web dashboard (http://localhost:9119). Change them before exposing any port.
HERMES_USER=hermes
HERMES_PASSWORD=hermes123
```

- [ ] **Step 4: Rewrite `README.md`** (the literal content — adjust only if a fact changed during implementation):

````markdown
# Hermes Agent Desktop Docker

A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed and its **`computer_use`** toolset wired to the desktop's `:1`
display — so the agent can drive a real GUI and a visible browser while you
watch and steer over the web, VNC, or RDP.

## Quick start

```bash
cp .env.example .env        # then edit HERMES_USER / HERMES_PASSWORD
docker compose up -d
```

Then open the **dashboard** at <http://localhost:9119> and set a model + API key
(Nous Portal recommended) in the API Keys tab, or run `hermes setup` from the
"Hermes Setup" desktop shortcut.

## Access

| Surface | Address | Login |
|---|---|---|
| Web desktop (NoVNC) | <http://localhost:6080/vnc.html> | VNC password = `HERMES_PASSWORD` |
| Raw VNC client | `localhost:5901` | `HERMES_PASSWORD` |
| RDP client | `localhost:3390` | `HERMES_USER` / `HERMES_PASSWORD` |
| Web dashboard | <http://localhost:9119> | `HERMES_USER` / `HERMES_PASSWORD` |

All three remote-desktop paths converge on the **same** `:1` desktop, so the
agent's `computer_use` actions are visible no matter how you connect
(see `docs/ACCESS-MODEL.md`). Default credentials are `hermes` / `hermes123` —
**change them before exposing any port beyond loopback.**

## What the agent can do

- **`computer_use`** — reads the AT-SPI accessibility tree and injects input via
  XTest on `:1` (enabled by default; `hermes computer-use doctor` to check).
- **Visible browser** — launch Chrome on `:1` with `--remote-debugging-port=9222`
  and `/browser connect` attaches to it over CDP so you can watch.
- **Dashboard** — Status, Chat (embedded TUI), Config, API Keys, Sessions,
  Skills, MCP, Logs, Cron, Channels.

## Configuration

- `HERMES_USER` / `HERMES_PASSWORD` — desktop account, used for VNC/RDP and the
  dashboard login. Set in `.env`.
- Per-user state persists in the `hermes-home` Docker volume (`~/.hermes`).
- Model/provider are unset by default — configure at runtime in the dashboard.

## Security

- The dashboard binds `0.0.0.0` inside the container but is host-published to
  `127.0.0.1:9119` only, and **always requires login** (scrypt-hashed password
  auth; no plaintext stored). LAN exposure is opt-in — edit the port mappings in
  `docker-compose.yml` and use a strong `HERMES_PASSWORD`.
- The VNC password and dashboard auth material are generated at container start
  (mode 600, in-container only) — never baked into the image or committed.

## Ports

`6080` NoVNC · `5901` VNC · `3390→3389` RDP · `9119` dashboard · `9222` CDP (in-container).
````

- [ ] **Step 5: Write `DOCKERHUB_OVERVIEW.md`** — a trimmed copy of the README's intro + Access + Security sections, suitable for the Docker Hub description (no repo-relative links; spell out that this is the `hermes-desktop` image). Keep it under ~100 lines. (Publishing it to Docker Hub is a later, separately-gated step that needs `docker login` — not part of this plan.)

- [ ] **Step 6: Verify**

Run: `./scripts/verify-docs.sh`
Expected: `[verify-docs] PASS`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "docs(2c): .env.example, full README, Docker Hub overview"
```

---

### Task 8: Deferred-Minors sweep + final review gate

**Files:**
- Modify: `<repo>/scripts/verify-rdp.sh` (add the `xrdp-sesman` check)
- Modify: `<repo>/Dockerfile` (drop the misleading `ENV HERMES_HOME=/root/.hermes`)
- Modify: `<repo>/entrypoint.sh` (optional: move build-time-stable `chown` out of the hot path — only if trivially safe)

**Interfaces:**
- Consumes: the full 2C image.
- Produces: the remaining 2B/spike-deferred Minors closed, plus a clean review pass.

- [ ] **Step 1: Add the sesman check to `scripts/verify-rdp.sh`**

After the `xrdp process healthy` block, before `PASS`:

```bash
echo "[verify-rdp] xrdp-sesman running?"
docker exec "$C" pgrep -x xrdp-sesman >/dev/null && echo "  OK sesman" || { echo "  FAIL sesman not running"; exit 1; }
```

- [ ] **Step 2: Drop the misleading `ENV HERMES_HOME`** — Hermes runs as `hermes` (uid 1000), so `ENV HERMES_HOME=/root/.hermes` (set at `Dockerfile:34`, now inside the Task 6 combined block) is never the runtime home and can mislead. Remove the `ENV HERMES_HOME=/root/.hermes` line. Verify the build still installs cleanly (install.sh uses root's real `$HOME` during the build regardless).

- [ ] **Step 3: Rebuild + run the FULL gate suite**

```bash
docker compose down -v && ./scripts/spike-up.sh
./scripts/verify-hermes.sh && ./scripts/verify-gonogo.sh && ./scripts/verify-dashboard.sh \
  && ./scripts/verify-desktop-shortcuts.sh && ./scripts/verify-quiet-boot.sh \
  && ./scripts/verify-env-clean.sh && ./scripts/verify-slim.sh \
  && ./scripts/verify-rdp.sh && ./scripts/verify-rdp-converge.sh \
  && ./scripts/verify-persistence.sh && ./scripts/verify-identity.sh \
  && ./scripts/verify-config-seed.sh && ./scripts/verify-init.sh && ./scripts/verify-docs.sh
```

Expected: every script PASS / `GO ✅`.

- [ ] **Step 4: Fresh-eyes review pass**

Run `/code-review` (or `/simplify`) over the full 2C diff (`git diff 387fecf..HEAD`). Triage findings: fix anything Important inline (with its own verify + commit); log any deferred Minor in the commit message. This is the "fresh review pass in 2C" the 2B handoff asked for.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore(2c): close deferred Minors — verify-rdp sesman check, drop misleading ENV HERMES_HOME"
```

---

## Out of scope (later follow-ons, not 2C)

- **Multi-arch (arm64 → Chromium).** amd64 only for now.
- **Pushing the image to Docker Hub / publishing `DOCKERHUB_OVERVIEW.md`** — needs `docker login` and is a separate gated action.
- **Full multi-stage Dockerfile rewrite** — Task 6 does an in-layer purge instead; revisit only if more slimming is needed (flagged decision).
- **`hermes gateway`/8642 API auto-start, s6 supervision, PUID/PGID remap** — official-image parity, adopt only if needed.

## Self-Review

- **Spec/scope coverage (2C as defined by the design doc + the 2B "Phase 2C (deferred)" handoff):** dashboard auto-start 9119 + basic-auth (design Goal #1, Layer ⑤, Decision #2) → Task 2; Hermes Dashboard shortcut (Layer ⑥) → Task 3; pin Hermes (open-Q #4, spike follow-up #2) → Task 1; image slim (spike #3) → Task 6; cua systemd warning (spike #1) + gail (spike #4) → Task 4; inert `.bashrc` + legacy `.profile` sweep → Task 5; `.env.example` + README + Docker Hub overview → Task 7; deferred-Minors (`verify-rdp` sesman, `verify-hermes` assertion, drop `ENV HERMES_HOME`) + fresh review → Task 8. Multi-arch + image push are explicitly out of scope, not gaps.
- **Placeholder scan:** no "TBD"/"add error handling". Every code/config block is literal; the one deliberately-prose deliverable (the Docker Hub overview body, Task 7 Step 5) is bounded by `verify-docs.sh` (must be non-empty) and described concretely.
- **Type/name/value consistency:** container `hermes-desktop`; user `${HERMES_USER:-hermes}`/`$USER`; ports 6080/5901/3389→3390/**9119**/9222; pinned commit `dd0e4ab81abccf7df5b11c6c16853d5e5de9db69` and version `v0.17.0 (2026.6.19)` used identically in Task 1's Dockerfile + `verify-hermes.sh`; dashboard env keys `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`/`_PASSWORD_HASH`/`_SECRET` match the installed `BasicAuthProvider`; auth file `~/.hermes/dashboard.env` + secret `~/.hermes/.dashboard-secret`; venv `/usr/local/lib/hermes-agent/venv/bin/python`; web dist `/usr/local/lib/hermes-agent/web/dist`; shim `/opt/hermes-noop/systemctl`. New verify scripts (`verify-dashboard`/`quiet-boot`/`env-clean`/`slim`/`docs`) follow the existing `#!/usr/bin/env bash` + `set -euo pipefail` + `C=hermes-desktop` + `[verify-X] … PASS` convention.
- **Regression guard:** every task re-runs `verify-gonogo.sh`; volume-touching tasks re-run `verify-persistence.sh`; Task 6 and Task 8 run the entire suite. Fresh-volume requirement is called out for Tasks 2/4/5/6 (first-boot guards).
- **Flagged decisions for the review gate:** (a) in-layer purge vs. full multi-stage (Task 6); (b) no-op `systemctl` shim vs. document-the-warning (Task 4 fallback). Both are reversible and recorded.
- **Ordering rationale:** pin first (deterministic rebuilds) → dashboard (the load-bearing feature) → its shortcut → warning/`.bashrc` cleanups → slim last among Dockerfile changes (so the purge accounts for every prior layer addition, and Task 2's standalone web-build `RUN` is folded in) → docs → minors + full review.

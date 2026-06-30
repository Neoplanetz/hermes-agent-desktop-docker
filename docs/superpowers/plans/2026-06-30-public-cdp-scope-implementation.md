> ⚠️ **HISTORICAL / SUPERSEDED.** This plan captured the cua-driver-removal round. Two later review rounds changed the end state: `9222` was removed from `EXPOSE` (CDP is loopback-only), `scripts/verify-atspi.sh` was deleted, and the AT-SPI/XTest tooling was removed. Treat specifics below as point-in-time; the repo is the source of truth.

# Public CDP Scope — Implementation Plan (remove cua-driver)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope the public image to secure, zero-privilege CDP browser automation by removing cua-driver (native `computer_use` desktop input is out of scope), while keeping the CDP Chrome + Hermes `/browser`, the XFCE/VNC/RDP/dashboard desktop, persistence, and all non-cua verify gates green.

**Architecture:** cua-driver is only the (out-of-scope) `computer_use` toolset; Hermes `/browser` is a standalone CDP client (`hermes_cli/browser_connect.py`, default `127.0.0.1:9222`) independent of it. So we strip the `hermes computer-use install` step + its build-time scaffolding, keep the visible CDP Chrome autostart, and prune/rewire the six verify gates that asserted cua health. Verification builds a **candidate image tag** and tests an **isolated container** so the running `hermes-desktop` and the published `:latest` are never disturbed until the candidate passes.

**Tech Stack:** Docker, bash (entrypoint + verify scripts), TigerVNC `Xvnc`, XFCE, xrdp, google-chrome-stable (CDP), Hermes Agent 0.17.0.

## Global Constraints

- Repo: `hermes-agent-desktop-docker`. Work on a branch/worktree (not directly on `main`) created at execution time.
- **Do not disturb** the running `hermes-desktop` container or the published Docker Hub `:latest` until the candidate image is verified (Task 4). Build candidates to tag `hermes-desktop:cdp-test`; test in a container named `hermes-cdp-test` on alternate loopback ports.
- **Keep** the visible CDP Chrome autostart on `:1` (entrypoint) and the Chrome `--no-sandbox` wrapper (Dockerfile). Hermes `/browser` attaches to it.
- Product docs (README.md, DOCKERHUB_OVERVIEW.md, docs/E2E-ACCEPTANCE.md) are pushed; planning docs under `docs/superpowers/` are committed locally, **not pushed**.
- Republishing to Docker Hub is **out of scope** for this plan (separate step, only if asked).
- Default credentials remain `hermes` / `hermes123` (documented dev default) — `verify-docs.sh` greps for `hermes123` + ports `6080/5901/3390/9119`, which must stay present in README.

---

### Task 1: Remove cua-driver install from entrypoint.sh (keep config seed + CDP Chrome)

**Files:**
- Modify: `entrypoint.sh:162-185`

**Interfaces:**
- Consumes: nothing new.
- Produces: an entrypoint that seeds `~/.hermes/{config.yaml,SOUL.md}` and still autostarts the CDP Chrome on `:1`, but performs **no** `hermes computer-use install` and writes **no** `.cua-installed` marker.

- [ ] **Step 1: Reword the section header comment**

Replace (`entrypoint.sh:162`):
```bash
# --- computer_use / cua-driver setup ---
```
with:
```bash
# --- config.yaml / SOUL.md seed (formerly also computer_use/cua-driver setup) ---
```

- [ ] **Step 2: Delete the cua-driver install block**

Remove these lines (`entrypoint.sh:173-185` — the blank line before the comment through the closing `fi`):
```bash

# Install cua-driver once (needs network on first boot)
if [ ! -f /home/$USER/.hermes/.cua-installed ]; then
  # Pre-create ~/.local/bin so ~/.profile adds it to PATH at next login-shell
  # startup; without this the directory doesn't exist yet on a fresh volume
  # and shutil.which("cua-driver") can't find the just-installed binary.
  su - "$USER" -c 'mkdir -p ~/.local/bin'
  if su - "$USER" -c 'PATH=/opt/hermes-noop:$PATH DISPLAY=:1 hermes computer-use install'; then
    su - "$USER" -c 'touch ~/.hermes/.cua-installed'
  else
    echo "WARN: hermes computer-use install failed (see logs)"
  fi
fi
```
Leave the `chown -R "$USER:$USER" "/home/$USER/.hermes"` line (162-block's last seed line) and the `# ── Visible CDP browser …` block that follows **untouched**.

- [ ] **Step 3: Static check the script parses**

Run: `bash -n entrypoint.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Confirm no cua-install references remain in entrypoint**

Run: `grep -nE 'computer-use install|\.cua-installed|hermes-noop' entrypoint.sh`
Expected: no matches (empty output).

- [ ] **Step 5: Commit**

```bash
git add entrypoint.sh
git commit -m "refactor(entrypoint): drop cua-driver install; keep config seed + CDP Chrome"
```

---

### Task 2: Remove cua-driver scaffolding from Dockerfile

**Files:**
- Modify: `Dockerfile:121-134`

**Interfaces:**
- Consumes: nothing.
- Produces: an image with no `/etc/profile.d/hermes-cdp.sh` (CUA_DRIVER_CDP_PORT) and no `/opt/hermes-noop/systemctl` shim. Chrome `--no-sandbox` wrapper (Dockerfile:50) and `EXPOSE … 9222 …` (Dockerfile:137) stay.

- [ ] **Step 1: Delete the CUA_DRIVER_CDP_PORT profile.d block**

Remove (`Dockerfile:121-126`):
```dockerfile
# Point cua-driver + Hermes /browser at the visible Chrome's CDP endpoint so the
# `page` toolset uses CDP (DOM-level: execute_javascript / query_dom / click_element)
# instead of the read-only AT-SPI fallback. Rootfs file — reaches every `su -` login
# shell that runs hermes/cua-driver. (The visible CDP Chrome is launched in entrypoint.sh.)
RUN printf 'export CUA_DRIVER_CDP_PORT=9222\n' > /etc/profile.d/hermes-cdp.sh \
    && chmod 0644 /etc/profile.d/hermes-cdp.sh
```
(Rationale: Hermes `/browser` defaults to `http://127.0.0.1:9222` on its own — `hermes_cli/browser_connect.py:DEFAULT_BROWSER_CDP_PORT = 9222` — so this env is unnecessary once cua-driver is gone.)

- [ ] **Step 2: Delete the no-op systemctl shim block**

Remove (`Dockerfile:128-134`):
```dockerfile
# No-op systemctl shim — retained for forward-compat (cua --autostart or future
# upstream changes). The active cua-warning fix is `mkdir -p ~/.local/bin` in
# entrypoint.sh (so shutil.which finds cua-driver). Does NOT shadow the real
# /usr/bin/systemctl globally; used only via PATH-prefix on the install call.
RUN mkdir -p /opt/hermes-noop \
    && printf '#!/bin/sh\nexit 0\n' > /opt/hermes-noop/systemctl \
    && chmod 0755 /opt/hermes-noop/systemctl
```

- [ ] **Step 3: Confirm no cua references remain in Dockerfile**

Run: `grep -niE 'cua|hermes-noop|CUA_DRIVER' Dockerfile`
Expected: only the line-50 comment may remain (`… (CDP/computer-use).`) — acceptable, it documents the Chrome wrapper. No `RUN`/`ENV`/profile.d cua lines.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "build: drop CUA_DRIVER_CDP_PORT profile.d + hermes-noop systemctl shim"
```

---

### Task 3: Rewire the verify gates off cua-driver

**Files:**
- Delete: `scripts/verify-doctor.sh`
- Modify: `scripts/verify-gonogo.sh:7-9`
- Modify: `scripts/verify-quiet-boot.sh` (drop cua-warning + doctor steps)
- Modify: `scripts/verify-e2e.sh:8-15` (drop `.cua-installed` wait)
- Modify: `scripts/verify-persistence.sh:21-23` (drop cua doctor)
- Modify: `scripts/verify-config-seed.sh:10-12` (drop doctor)
- Modify: `scripts/verify-cdp.sh:7-8,23-26` (drop CUA_DRIVER_CDP_PORT; reframe to /browser)

**Interfaces:**
- Produces: a gate suite with no `hermes computer-use doctor` / `.cua-installed` dependency. `verify-cdp.sh` proves the CDP endpoint `/browser` attaches to is live.

- [ ] **Step 1: Delete the cua-only doctor gate**

Run:
```bash
git rm scripts/verify-doctor.sh
```
(No aggregator references it; `verify-e2e.sh` calls `verify-gonogo.sh`, not `verify-doctor.sh`.)

- [ ] **Step 2: verify-gonogo.sh — replace the doctor check with a Hermes-CLI health check**

Replace (`scripts/verify-gonogo.sh:7-9`):
```bash
echo "[1/4] hermes computer-use doctor"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null || fail "doctor"
echo "  OK"
```
with:
```bash
echo "[1/4] hermes CLI healthy (no cua-driver required)"
docker exec "$C" su - hermes -c 'hermes --help >/dev/null 2>&1' || fail "hermes CLI"
echo "  OK"
```
(Steps [2/4] XTest, [3/4] AT-SPI, [4/4] CDP stay — they exercise the desktop + CDP, not cua-driver.)

- [ ] **Step 3: verify-quiet-boot.sh — drop the cua-warning and doctor steps**

Replace the whole file body after the shebang with:
```bash
#!/usr/bin/env bash
# Boot-hygiene gate: GTK_MODULES carries no legacy `gail` (config-state assertion,
# platform-independent). Run AFTER a fresh boot.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] GTK_MODULES has no gail (atk-bridge only)?"
docker exec "$C" su - hermes -c 'cat ~/.xprofile 2>/dev/null' | grep -E '^export GTK_MODULES' | grep -qw gail \
  && { echo "  FAIL gail still in GTK_MODULES"; exit 1; } || echo "  OK atk-bridge only (no gail)"
echo "[verify-quiet-boot] PASS"
```
(The `cua-driver installing did not complete` warning is impossible once cua-driver isn't installed, and the doctor check is gone.)

- [ ] **Step 4: verify-e2e.sh — drop the `.cua-installed` wait**

Replace (`scripts/verify-e2e.sh:8-15`):
```bash
echo "[e2e] waiting for first-boot cua install to complete…"
for i in $(seq 1 120); do
  docker exec "$C" test -f "/home/$U/.hermes/.cua-installed" 2>/dev/null && break
  sleep 2
done
docker exec "$C" test -f "/home/$U/.hermes/.cua-installed" \
  || { echo "  FAIL cua-install timeout (240s)"; exit 1; }
echo "  OK cua installed"
```
with:
```bash
echo "[e2e] waiting for :1 desktop to come up…"
for i in $(seq 1 60); do
  docker exec "$C" su - "$U" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break
  sleep 2
done
docker exec "$C" su - "$U" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' \
  || { echo "  FAIL :1 never came up (120s)"; exit 1; }
echo "  OK desktop up"
```

- [ ] **Step 5: verify-persistence.sh — drop the cua doctor step**

Remove (`scripts/verify-persistence.sh:21-23`):
```bash
echo "[verify-persistence] cua-driver still functional after recreate (no reinstall)?"
docker exec "$C" su - "$U" -c 'DISPLAY=:1 hermes computer-use doctor >/dev/null' \
  && echo "  OK cua survived recreate" || { echo "  FAIL cua lost on recreate"; exit 1; }
```
(The `persist-probe` survival check on lines 19-20 already proves volume persistence.)

- [ ] **Step 6: verify-config-seed.sh — drop the doctor step**

Remove only these three lines (`scripts/verify-config-seed.sh:10-12`):
```bash
echo "[verify-config-seed] doctor still green?"
docker exec "$C" su - "$U" -c 'DISPLAY=:1 hermes computer-use doctor >/dev/null' \
  && echo "  OK doctor" || { echo "  FAIL doctor"; exit 1; }
```
The existing final line `echo "[verify-config-seed] PASS"` (formerly line 13) stays and becomes the new end of the file. The model-unset check (lines 7-9) is now the last assertion.

- [ ] **Step 7: verify-cdp.sh — drop CUA_DRIVER_CDP_PORT, reframe to /browser**

Replace the comment (`scripts/verify-cdp.sh:7-8`):
```bash
# answers CDP on :9222, and that CUA_DRIVER_CDP_PORT reaches login shells so
# cua-driver's `page` tool uses CDP instead of the read-only AT-SPI fallback.
```
with:
```bash
# answers CDP on :9222 — the endpoint Hermes `/browser` attaches to
# (hermes_cli/browser_connect.py defaults to http://127.0.0.1:9222).
```
Then remove the CUA_DRIVER_CDP_PORT block (`scripts/verify-cdp.sh:23-26`):
```bash
echo "[cdp] CUA_DRIVER_CDP_PORT=9222 exported to login shells"
docker exec "$C" su - "$U" -c '[ "${CUA_DRIVER_CDP_PORT:-}" = "9222" ]' \
  && echo "  OK CUA_DRIVER_CDP_PORT=9222" \
  || { echo "  FAIL CUA_DRIVER_CDP_PORT not set in login shell"; exit 1; }
```
and add a CDP-functional check in its place:
```bash
echo "[cdp] CDP accepts a new target (Hermes /browser attach surface)"
docker exec "$C" bash -lc 'curl -fsS -X PUT http://127.0.0.1:9222/json/new?about:blank >/dev/null' \
  && echo "  OK CDP target-creation works" \
  || { echo "  FAIL CDP did not create a target"; exit 1; }
```

- [ ] **Step 8: Confirm no `computer-use doctor` / `.cua-installed` remains in scripts**

Run: `grep -rnE 'computer-use doctor|\.cua-installed|CUA_DRIVER' scripts/`
Expected: no matches.

- [ ] **Step 9: Commit**

```bash
git add -A scripts/
git commit -m "test: rewire verify gates off cua-driver (delete verify-doctor; /browser-based CDP gate)"
```

---

### Task 4: Build candidate image + verify Hermes boots cleanly without cua-driver (isolated)

**Files:** none (build + run verification only).

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a verified candidate image `hermes-desktop:cdp-test`. The running `hermes-desktop` and `:latest` are untouched.

- [ ] **Step 1: Build the candidate image**

Run: `docker build -t hermes-desktop:cdp-test .`
Expected: build succeeds; final `naming to docker.io/library/hermes-desktop:cdp-test`.

- [ ] **Step 2: Boot an isolated test container on alternate loopback ports + fresh volume**

Run:
```bash
docker rm -f hermes-cdp-test 2>/dev/null
docker volume rm hermes-cdp-test-home 2>/dev/null
docker run -d --name hermes-cdp-test \
  -e HERMES_USER=hermes -e HERMES_PASSWORD=hermes123 \
  -p 127.0.0.1:16080:6080 -p 127.0.0.1:15901:5901 \
  -p 127.0.0.1:13390:3389 -p 127.0.0.1:19119:9119 \
  -v hermes-cdp-test-home:/home/hermes \
  --shm-size 2gb --security-opt seccomp=unconfined --init \
  hermes-desktop:cdp-test
```
Expected: prints a container id.

- [ ] **Step 3: Wait for the desktop, then assert a clean, cua-free boot**

Run:
```bash
for i in $(seq 1 45); do docker exec hermes-cdp-test su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break; sleep 2; done
echo "--- cua/error scan of boot log ---"
docker logs hermes-cdp-test 2>&1 | grep -iE 'cua|computer-use|traceback|did not complete' || echo "OK: no cua/computer-use/traceback lines"
```
Expected: `OK: no cua/computer-use/traceback lines`.

- [ ] **Step 4: Assert Hermes CLI runs without cua-driver installed**

Run: `docker exec hermes-cdp-test su - hermes -c 'hermes --help >/dev/null 2>&1 && echo HERMES_CLI_OK'`
Expected: `HERMES_CLI_OK`. Also confirm cua-driver is absent: `docker exec hermes-cdp-test su - hermes -c 'command -v cua-driver || echo NO_CUA'` → `NO_CUA`.

- [ ] **Step 5: Assert the CDP endpoint (the /browser attach target) is live + functional**

Run:
```bash
docker exec hermes-cdp-test bash -lc 'for i in $(seq 1 20); do curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break; sleep 2; done; curl -fsS http://127.0.0.1:9222/json/version >/dev/null && curl -fsS -X PUT "http://127.0.0.1:9222/json/new?about:blank" >/dev/null && echo CDP_OK'
```
Expected: `CDP_OK`.

- [ ] **Step 6: Run the rewired CDP gate against the test container**

Run: `HERMES_USER=hermes scripts/verify-cdp.sh hermes-cdp-test`
Expected: ends with `[cdp] PASS`.

- [ ] **Step 7: Tear down the test container (keep the candidate image)**

Run:
```bash
docker rm -f hermes-cdp-test
docker volume rm hermes-cdp-test-home
```
Expected: both removed. (No commit — verification only.)

---

### Task 5: Decide the `seccomp=unconfined` security setting

**Files:**
- Modify: `docker-compose.yml:22` (and `DOCKERHUB_OVERVIEW.md` run example if the setting is removed)

**Interfaces:**
- Produces: either a removed `security_opt` (preferred, least-privilege) or a one-line documented justification.

- [ ] **Step 1: Test whether the desktop + CDP work WITHOUT `seccomp=unconfined`**

Run (rebuild not needed; reuse candidate image, omit the seccomp opt):
```bash
docker rm -f hermes-cdp-test 2>/dev/null; docker volume rm hermes-cdp-test-home 2>/dev/null
docker run -d --name hermes-cdp-test -e HERMES_USER=hermes -e HERMES_PASSWORD=hermes123 \
  -p 127.0.0.1:16080:6080 -p 127.0.0.1:19119:9119 \
  -v hermes-cdp-test-home:/home/hermes --shm-size 2gb --init hermes-desktop:cdp-test
for i in $(seq 1 45); do docker exec hermes-cdp-test su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break; sleep 2; done
docker exec hermes-cdp-test su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && echo "DESKTOP_OK (no seccomp opt)" || echo "DESKTOP_FAIL"
docker exec hermes-cdp-test bash -lc 'for i in $(seq 1 20); do curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break; sleep 2; done; curl -fsS http://127.0.0.1:9222/json/version >/dev/null && echo "CDP_OK (no seccomp opt)" || echo "CDP_FAIL"'
```
Expected (decision branch): if both print `…_OK`, the setting is unnecessary → Step 2a. If either FAILs, it's required → Step 2b.

- [ ] **Step 2a (if OK): Remove the loosening from compose**

Edit `docker-compose.yml` — delete line 22:
```yaml
    security_opt: [ "seccomp=unconfined" ]
```

- [ ] **Step 2b (if required): Keep it, but document why (one line)**

Edit `docker-compose.yml:22` to add a trailing comment:
```yaml
    security_opt: [ "seccomp=unconfined" ]  # required: <exact failing component from Step 1, e.g. Chrome/xrdp>
```

- [ ] **Step 3: Tear down the test container**

Run: `docker rm -f hermes-cdp-test; docker volume rm hermes-cdp-test-home`

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "security: drop seccomp=unconfined (verified unnecessary)"   # or: "document seccomp=unconfined requirement"
```

---

### Task 6: Reframe the product docs to the CDP scope

**Files:**
- Modify: `README.md:3-6,29,35-40`
- Modify: `DOCKERHUB_OVERVIEW.md:3-6,48,54-57`

**Interfaces:**
- Produces: docs whose headline capability is secure CDP browser automation + observable desktop; `computer_use` native input framed as a documented limitation (existing README "Known limitations" stays, links `docs/E2E-ACCEPTANCE.md`). README keeps `6080/5901/3390/9119/hermes123` (for `verify-docs.sh`).

- [ ] **Step 1: README headline (lines 3-6)**

Replace:
```markdown
A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed and its **`computer_use`** toolset wired to the desktop's `:1`
display — so the agent can drive a real GUI and a visible browser while you
watch and steer over the web, VNC, or RDP.
```
with:
```markdown
A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed for **secure browser automation**: a CDP-enabled Chrome runs on
the `:1` display and Hermes' `/browser` drives it, while you watch and steer over
the web (NoVNC), VNC, or RDP. Runs with **no extra privilege** (`docker compose up`).
```

- [ ] **Step 2: README "agent actions visible" line (29)**

Replace:
```markdown
agent's `computer_use` actions are visible no matter how you connect
```
with:
```markdown
agent's browser actions are visible no matter how you connect
```

- [ ] **Step 3: README "What the agent can do" (lines 35-40)**

Replace:
```markdown
- **`computer_use`** — reads the desktop's window list + AT-SPI accessibility tree
  on `:1` and drives apps via cua-driver (`hermes computer-use doctor` to check).
  ⚠️ Keyboard input into native GTK apps does not work yet — see **Known limitations**.
- **Visible browser** — a CDP-enabled Chrome autostarts on `:1`; `/browser connect`
  and the agent's `page` tool attach over CDP (`:9222`) so the agent can read/drive
  the page while you watch.
```
with:
```markdown
- **Browser automation (CDP)** — a CDP-enabled Chrome autostarts on `:1`; Hermes
  `/browser` attaches over CDP (`127.0.0.1:9222`, never exposed to the host) so the
  agent can read and drive web pages while you watch over NoVNC/RDP.
- **Observable desktop** — NoVNC / VNC / RDP all show the same `:1` session, so you
  can watch the automation live and intervene by hand.
```
(The "Known limitations" section on lines 44-60 stays as-is — it already documents that native `computer_use` desktop input is unsupported in this VNC model and links `docs/E2E-ACCEPTANCE.md`.)

- [ ] **Step 4: DOCKERHUB_OVERVIEW headline (lines 3-6)**

Replace:
```markdown
A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed and its **`computer_use`** toolset wired to the desktop's `:1`
display — so the agent can drive a real GUI and a visible browser while you
watch and steer over the web, VNC, or RDP.
```
with:
```markdown
A turnkey Ubuntu 24.04 + XFCE4 desktop with **Hermes Agent** (Nous Research)
pre-installed for **secure browser automation**: a CDP-enabled Chrome runs on
the `:1` display and Hermes' `/browser` drives it, while you watch and steer over
the web (NoVNC), VNC, or RDP. Runs with **no extra privilege** (`docker compose up`).
```

- [ ] **Step 5: DOCKERHUB_OVERVIEW "actions visible" (line 48)**

Replace:
```markdown
agent's `computer_use` actions are visible no matter how you connect.
```
with:
```markdown
agent's browser actions are visible no matter how you connect.
```

- [ ] **Step 6: DOCKERHUB_OVERVIEW "What the agent can do" (lines 54-57)**

Replace:
```markdown
- **`computer_use`** — reads the AT-SPI accessibility tree and injects input via
  XTest on `:1` (enabled by default; `hermes computer-use doctor` to check).
- **Visible browser** — launch Chrome on `:1` with `--remote-debugging-port=9222`
  and `/browser connect` attaches to it over CDP so you can watch.
```
with:
```markdown
- **Browser automation (CDP)** — a CDP-enabled Chrome autostarts on `:1`; Hermes
  `/browser` attaches over CDP (`127.0.0.1:9222`) so the agent reads and drives web
  pages while you watch. (Native `computer_use` desktop input is not supported under
  this VNC desktop — see the project README / `docs/E2E-ACCEPTANCE.md`.)
```

- [ ] **Step 7: Run the docs gate**

Run: `scripts/verify-docs.sh`
Expected: `[verify-docs] PASS` (README still contains `6080/5901/3390/9119/hermes123`).

- [ ] **Step 8: Commit**

```bash
git add README.md DOCKERHUB_OVERVIEW.md
git commit -m "docs: reframe scope to secure CDP browser automation; computer_use native input out of scope"
```

---

### Task 7: Final full-suite verification on the swapped image + size check

**Files:** none (swap + verify + summary).

**Interfaces:**
- Consumes: Tasks 1-6 (all committed on the branch).
- Produces: the real `hermes-desktop:latest` rebuilt from the new source, all non-cua gates green, image size recorded. (No Docker Hub push.)

- [ ] **Step 1: Rebuild the real image tag from the new source**

Run: `docker build -t hermes-desktop:latest .`
Expected: build succeeds.

- [ ] **Step 2: Recreate the local desktop from the new image**

Run: `docker compose up -d --force-recreate`
Wait: `for i in $(seq 1 45); do docker exec hermes-desktop su - hermes -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break; sleep 2; done`
Expected: container healthy within `start_period` (90s) — check `docker ps --filter name=hermes-desktop --format '{{.Status}}'` shows `healthy`.

- [ ] **Step 3: Run every non-cua verify gate**

Run:
```bash
for g in verify-init verify-identity verify-desktop verify-rdp verify-rdp-converge \
         verify-dashboard verify-desktop-shortcuts verify-atspi verify-cdp \
         verify-config-seed verify-persistence verify-quiet-boot verify-hermes \
         verify-env-clean verify-slim verify-docs verify-gonogo; do
  echo "=== $g ==="; HERMES_USER=hermes scripts/$g.sh hermes-desktop || echo "!!! $g FAILED"
done
```
Expected: every gate ends in `PASS`/`OK`/`GO`; no `!!! … FAILED` line. (`verify-doctor` is intentionally gone.)

- [ ] **Step 4: Record the image size (expect a drop from cua-driver removal)**

Run: `docker images hermes-desktop:latest --format '{{.Size}}'`
Expected: a size less than or equal to the prior `:latest` (~6.06 GB); note the new value.

- [ ] **Step 5: Final commit (summary / any gate fixups)**

```bash
git add -A
git commit -m "chore: finalize CDP-scope image (cua-driver removed); all non-cua gates green" --allow-empty
```

- [ ] **Step 6: Report**

Summarize to the user: branch name, commits, the seccomp decision (Step 5/Task 5 outcome), the new image size vs old, and that Docker Hub republish is a separate step awaiting their go-ahead. Planning docs (this plan + the spec) stay committed locally, unpushed; product doc + code changes are ready to push to `main` on approval.

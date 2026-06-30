> ⚠️ **HISTORICAL — pre-pivot.** This document predates the **2026-06-30 pivot** to a public image. It describes the original `computer_use` / **cua-driver** native desktop-input ambition (AT-SPI tree + XTest), which was **proven insecure under this VNC/container model and dropped** — native desktop input is now a documented **non-goal**. The shipped product is **secure, zero-privilege CDP browser automation** (Hermes `/browser` → CDP Chrome on loopback `127.0.0.1:9222`). Current truth: `docs/superpowers/specs/2026-06-30-public-cdp-scope-design.md`, the README “Known limitations,” and the repo itself.

# Hermes Agent Desktop Docker — Phase 2A: Persistent, Configurable Base + Computer-Use E2E Gate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the validated Phase-1 spike into a **persistent, env-configurable** Hermes desktop — a named home volume that survives container recreate, first-boot seeding of `~/.hermes` config + persona, user/password from `.env` — and close the two gaps the spike deliberately skipped by validating the **model-in-the-loop `computer_use` loop on a fresh named volume**.

**Architecture:** Build directly on the spike repo `hermes-agent-desktop-docker` (`main`, currently at `3c8f0bb`). Port the proven OpenClaw Desktop Docker patterns — input validation, dynamic user creation, `/opt/*-defaults` home template copied on first boot (the volume-shadow fix), idempotent config seeding — adapting OpenClaw's npm/JSON specifics to Hermes' Python/`~/.hermes` layout. Each task keeps the spike's TDD-style cycle: write a `scripts/verify-*.sh` → run/fail → implement → rebuild → pass → commit.

**Tech Stack:** Docker (linux/amd64), Ubuntu 24.04, XFCE4, TigerVNC `Xvnc :1`, NoVNC, Hermes Agent (Python/uv), cua-driver, named Docker volume.

## Global Constraints

Carried from the design spec + spike; every task implicitly includes these:

- **Base/display unchanged from spike:** Ubuntu 24.04, XFCE4, TigerVNC `Xvnc :1` (1920x1080x24), NoVNC 6080, raw VNC 5901, linux/amd64. `entrypoint.sh` runs `set -euo pipefail`. The cua-driver/AT-SPI/computer_use wiring from Tasks 1–4 of the spike must keep working (`hermes computer-use doctor` stays green).
- **Agent/desktop user is unprivileged** (default `hermes`, uid 1000), never root for the session. `hermes` binary stays image-baked at `/usr/local/bin/hermes` (survives the home volume).
- **Identity from env:** `HERMES_USER` (default `hermes`) and `HERMES_PASSWORD` (default `hermes123`) come from `.env`/compose. Validate before use — `HERMES_USER` must match `^[a-z_][a-z0-9_-]{0,31}$`; `HERMES_PASSWORD` must not contain newline/CR/colon. (Ports OpenClaw's entrypoint validation verbatim.)
- **Persistence:** `/home/${HERMES_USER}` is a named Docker volume (`hermes-home`). Image-baked home content is shadowed by the empty volume on first run, so home contents (`.vnc`, `.xprofile`, `.hermes` config/persona, Desktop) are seeded from a build-time template at `/opt/hermes-defaults` on first boot **only if absent** (idempotent). The cua-install marker `~/.hermes/.cua-installed` and seeded config must survive `docker compose down && up`.
- **Model left unset:** seeded `~/.hermes/config.yaml` enables `computer_use` but sets no model/provider — configured at runtime (dashboard in 2C, or `hermes setup`). No secrets baked.
- **No secrets baked.** The default `hermes123` password is a published dev default (like OpenClaw's `claw1234`); compose binds ports to `127.0.0.1` only.
- **Image/container naming:** image `hermes-desktop`, container `hermes-desktop` (rename from the spike's `hermes-desktop-spike`/`hermes-spike`). Update all verify scripts' container references together.

---

### Task 1: Identity from env — validation, password sync, dynamic user creation

**Files:**
- Create: `<repo>/.env`
- Modify: `<repo>/docker-compose.yml` (env wiring, rename service/container/image, volume)
- Modify: `<repo>/Dockerfile` (rename labels; keep build user `hermes` as the template account)
- Modify: `<repo>/entrypoint.sh` (replace the hardcoded `USER=hermes`/`PASSWORD=hermes123` header with env + validation + dynamic user creation)
- Create: `<repo>/scripts/verify-identity.sh`
- Modify: the 5 existing `scripts/verify-*.sh` + `scripts/spike-up.sh` (container name `hermes-spike` → `hermes-desktop`)

**Interfaces:**
- Produces: a container named `hermes-desktop` whose session user and password come from `HERMES_USER`/`HERMES_PASSWORD`. Later tasks and all verify scripts use `docker exec hermes-desktop su - "$HERMES_USER" -c …`. The entrypoint exports `USER` (resolved) for downstream blocks.

- [ ] **Step 1: Write `.env`**

```bash
# Hermes Agent Desktop — user configuration
HERMES_USER=hermes
HERMES_PASSWORD=hermes123
```

- [ ] **Step 2: Write the failing test — `scripts/verify-identity.sh`**

```bash
#!/usr/bin/env bash
# Passes when the session user + password come from the environment.
set -euo pipefail
C=hermes-desktop
U="${HERMES_USER:-hermes}"
echo "[verify-identity] user '$U' exists, uid 1000, in sudo?"
docker exec "$C" id "$U" | grep -q 'uid=1000' || { echo "  FAIL uid"; exit 1; }
docker exec "$C" id "$U" | grep -q '(sudo)' || { echo "  FAIL sudo"; exit 1; }
echo "  OK user"
echo "[verify-identity] password matches HERMES_PASSWORD (su auth)?"
docker exec "$C" bash -c "echo '${HERMES_PASSWORD:-hermes123}' | su '$U' -c 'whoami'" | grep -q "^$U$" \
  || { echo "  FAIL password"; exit 1; }
echo "  OK password"
echo "[verify-identity] PASS"
```

- [ ] **Step 3: Run to verify it fails**

Run: `HERMES_USER=hermes ./scripts/verify-identity.sh`
Expected: FAIL — container is still `hermes-spike` (wrong name) / no env-driven password.

- [ ] **Step 4: Replace the `entrypoint.sh` header block** (lines 1–6, the `set -euo pipefail` + hardcoded user) with env + validation + dynamic creation. New top of file:

```bash
#!/bin/bash
set -euo pipefail

USER="${HERMES_USER:-hermes}"
PASSWORD="${HERMES_PASSWORD:-hermes123}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
VNC_COL_DEPTH="${VNC_COL_DEPTH:-24}"

# ── Input validation (USER/PASSWORD are interpolated into su/chpasswd) ──
if ! [[ "$USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "FATAL: invalid HERMES_USER '$USER' (must match ^[a-z_][a-z0-9_-]{0,31}$)"; exit 1
fi
case "$PASSWORD" in
    *[$'\n\r:']*) echo "FATAL: HERMES_PASSWORD contains newline, CR, or colon"; exit 1 ;;
esac

# ── Dynamic user creation (so HERMES_USER from env takes effect) ──
# The image bakes 'hermes' (uid 1000) as the template account. If a different
# HERMES_USER is requested, create it at runtime and seed its home from the
# build-time template (Task 2 installs /opt/hermes-defaults).
if ! id "$USER" &>/dev/null; then
    echo ">> Creating user '$USER'..."
    useradd -m -s /bin/bash "$USER"
    usermod -aG sudo "$USER"
    SUDOERS_TMP=$(mktemp)
    echo "$USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_TMP"
    if visudo -c -f "$SUDOERS_TMP" >/dev/null; then
        mv "$SUDOERS_TMP" /etc/sudoers.d/"$USER"; chmod 0440 /etc/sudoers.d/"$USER"
    else
        rm -f "$SUDOERS_TMP"; echo "FATAL: sudoers entry failed visudo"; exit 1
    fi
fi
# Always sync password (handles password-only changes without rebuild)
echo "$USER:$PASSWORD" | chpasswd
```

The remainder of `entrypoint.sh` already references `$USER`/`$PASSWORD`, so it works unchanged. (The build still bakes `hermes`; `visudo`/`useradd` are present in the base image.)

- [ ] **Step 5: Wire env in `docker-compose.yml`** — rename and add env + volume scaffold (the volume itself lands in Task 2; here just the service rename + env):

```yaml
services:
  hermes-desktop:
    build: { context: ., dockerfile: Dockerfile }
    image: hermes-desktop:latest
    container_name: hermes-desktop
    environment:
      - HERMES_USER=${HERMES_USER:-hermes}
      - HERMES_PASSWORD=${HERMES_PASSWORD:-hermes123}
    ports:
      - "127.0.0.1:6080:6080"
      - "127.0.0.1:5901:5901"
    shm_size: "2gb"
    security_opt: [ "seccomp=unconfined" ]
    restart: unless-stopped
```

- [ ] **Step 6: Rename `hermes-spike` → `hermes-desktop`** in `scripts/spike-up.sh` and every `scripts/verify-*.sh` (`docker exec hermes-spike` and any `su - hermes`→`su - "$USER"` where a custom user must work; for the default-path verifies, `hermes` literal is acceptable but update the container name). Also update the Dockerfile `LABEL`/comment header to "Hermes Agent Desktop".

- [ ] **Step 7: Rebuild + verify (default user, then a custom user)**

Run: `./scripts/spike-up.sh && HERMES_USER=hermes HERMES_PASSWORD=hermes123 ./scripts/verify-identity.sh`
Expected: `[verify-identity] PASS`.
Then a custom-user smoke check: `HERMES_USER=agent HERMES_PASSWORD=s3cret docker compose up -d --force-recreate` then `HERMES_USER=agent HERMES_PASSWORD=s3cret ./scripts/verify-identity.sh` → PASS (user `agent` created, password works). Reset back to `hermes` afterward.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(2a): identity from env — validation, password sync, dynamic user"
```

---

### Task 2: Named-volume persistence + home template (`/opt/hermes-defaults`)

**Files:**
- Modify: `<repo>/Dockerfile` (copy the baked home skeleton to `/opt/hermes-defaults`)
- Modify: `<repo>/docker-compose.yml` (add the `hermes-home` named volume)
- Modify: `<repo>/entrypoint.sh` (seed `/home/$USER` from the template on first boot if empty)
- Create: `<repo>/scripts/verify-persistence.sh`

**Interfaces:**
- Consumes: the env identity from Task 1.
- Produces: `/home/$USER` backed by the `hermes-home` volume; on a fresh volume, `.vnc`, `.xprofile`, and (Task 3) `.hermes` are seeded from `/opt/hermes-defaults`. Survives `docker compose down && up`.

- [ ] **Step 1: Write the failing test — `scripts/verify-persistence.sh`**

```bash
#!/usr/bin/env bash
# Passes when home is volume-backed, seeded on fresh volume, and persists.
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-persistence] /home/$U is a mount (volume)?"
docker exec "$C" sh -c "mount | grep -q ' /home/$U '" && echo "  OK mounted" || { echo "  FAIL not a mount"; exit 1; }
echo "[verify-persistence] template-seeded files present on this volume?"
docker exec "$C" su - "$U" -c 'test -f ~/.vnc/xstartup && test -f ~/.xprofile' \
  && echo "  OK seeded" || { echo "  FAIL not seeded"; exit 1; }
echo "[verify-persistence] write marker, recreate container, marker survives?"
docker exec "$C" su - "$U" -c 'echo persist-probe > ~/.persist-probe'
docker compose up -d --force-recreate >/dev/null
for i in $(seq 1 30); do docker exec "$C" su - "$U" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break; sleep 1; done
docker exec "$C" su - "$U" -c 'grep -q persist-probe ~/.persist-probe' \
  && echo "  OK persisted across recreate" || { echo "  FAIL lost on recreate"; exit 1; }
echo "[verify-persistence] PASS"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/verify-persistence.sh`
Expected: FAIL — `/home/$U` is not yet a volume mount.

- [ ] **Step 3: Bake the home template in the `Dockerfile`** — after the `hermes` user exists and its `.vnc`/`.xprofile` are created (these are created at runtime today by entrypoint, NOT at build). **Therefore move the static skeleton into the image:** add a Dockerfile step that materializes the template from the entrypoint's known-good content. Concretely, create `/opt/hermes-defaults` with the `.vnc/xstartup`, `.xprofile`, and an empty `Desktop/`:

```dockerfile
# Home template seeded onto the (volume-shadowed) home on first boot
RUN mkdir -p /opt/hermes-defaults/.vnc /opt/hermes-defaults/Desktop \
    && cp /home/hermes/.bashrc /opt/hermes-defaults/ 2>/dev/null || true
```

> Implementer note: the canonical `.vnc/xstartup` and `.xprofile` are currently written by `entrypoint.sh` at runtime (heredocs). Keep that as the source of truth — in Step 4 the entrypoint writes them into `/home/$USER` regardless (idempotently), so the template only needs to carry files NOT regenerated by the entrypoint (`.bashrc`, `Desktop/`). The entrypoint already rewrites `.vnc/xstartup` + `.xprofile` every boot, which is volume-safe. So this task's real job is (a) mount the volume and (b) guarantee the entrypoint's home writes happen AFTER the mount is present and chowned. Verify the entrypoint's `chown -R $USER:$USER /home/$USER/...` covers a freshly-mounted empty volume.

- [ ] **Step 4: Seed-on-first-boot in `entrypoint.sh`** — immediately after user creation/password sync, before the VNC block, ensure the home is owned and skeleton-seeded:

```bash
# ── First-boot home seed (volume-shadow fix) ──
# A fresh named volume mounts empty over /home/$USER, shadowing image content.
# Seed from the build-time template only when the home looks empty.
if [ -d /opt/hermes-defaults ] && [ ! -e "/home/$USER/.seeded" ]; then
    cp -an /opt/hermes-defaults/. "/home/$USER/" 2>/dev/null || true
    cp -an /etc/skel/. "/home/$USER/" 2>/dev/null || true
    : > "/home/$USER/.seeded"
fi
chown -R "$USER:$USER" "/home/$USER"
```

(The entrypoint's later `.vnc/xstartup`, `.xprofile`, `.hermes` writes remain — they are idempotent and run after this.)

- [ ] **Step 5: Add the named volume to `docker-compose.yml`**

```yaml
    volumes:
      - hermes-home:/home/${HERMES_USER:-hermes}
# … at file end:
volumes:
  hermes-home:
    name: hermes-home
```

- [ ] **Step 6: Rebuild on a clean volume + verify**

Run: `docker compose down -v` (drop any old volume), then `./scripts/spike-up.sh && ./scripts/verify-persistence.sh`
Expected: `[verify-persistence] PASS` (mounted, seeded, survives recreate). Then re-run `./scripts/verify-gonogo.sh` → still `GO ✅` (computer_use unaffected by the volume).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(2a): named-volume home persistence + first-boot template seed"
```

---

### Task 3: Hermes config + persona seeding (`~/.hermes/config.yaml`, `SOUL.md`)

**Files:**
- Modify: `<repo>/Dockerfile` (bake the config template into `/opt/hermes-defaults/.hermes/`)
- Modify: `<repo>/entrypoint.sh` (seed `~/.hermes/config.yaml` + `SOUL.md` on first boot if absent)
- Create: `<repo>/configs/config.yaml` (the seeded template)
- Create: `<repo>/scripts/verify-config-seed.sh`

**Interfaces:**
- Consumes: the persistent home from Task 2.
- Produces: on a fresh volume, `~/.hermes/config.yaml` (computer_use enabled, model unset) + `~/.hermes/SOUL.md`; persists across recreate; `hermes computer-use doctor` stays green.

- [ ] **Step 1: Confirm the canonical config schema, then write `configs/config.yaml`**

First read Hermes' own example to avoid inventing keys:
Run: `docker exec hermes-desktop bash -c 'find /usr/local/lib/hermes-agent -name "cli-config.yaml.example" -maxdepth 3'` then read it. Seed a MINIMAL valid subset — enable computer_use, leave model/provider unset. Starting point (reconcile against the example's key names):

```yaml
# Hermes Agent Desktop — seeded defaults. Set your model in the dashboard
# (Phase 2C) or via `hermes setup`. computer_use is pre-enabled for the
# XFCE :1 desktop.
computer_use:
  cua_telemetry: false
```

> If the example uses a different enable key (e.g. `tools:` / `enabled_tools:`), use that; the spike confirmed `computer_use:` is accepted and `hermes -t computer_use chat` enables the tool, so at minimum keep the spike's working block.

- [ ] **Step 2: Write the failing test — `scripts/verify-config-seed.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-config-seed] ~/.hermes/config.yaml + SOUL.md present?"
docker exec "$C" su - "$U" -c 'test -f ~/.hermes/config.yaml && test -f ~/.hermes/SOUL.md' \
  && echo "  OK seeded" || { echo "  FAIL missing"; exit 1; }
echo "[verify-config-seed] config has no model pinned (left for runtime)?"
docker exec "$C" su - "$U" -c 'grep -qiE "model:|provider:" ~/.hermes/config.yaml' \
  && { echo "  FAIL model pinned"; exit 1; } || echo "  OK model unset"
echo "[verify-config-seed] doctor still green?"
docker exec "$C" su - "$U" -c 'DISPLAY=:1 hermes computer-use doctor >/dev/null' \
  && echo "  OK doctor" || { echo "  FAIL doctor"; exit 1; }
echo "[verify-config-seed] PASS"
```

- [ ] **Step 3: Run to verify it fails**

Run: `./scripts/verify-config-seed.sh`
Expected: FAIL — only the spike's bare `config.yaml` exists (written inline by entrypoint), no `SOUL.md`, and config isn't template-driven.

- [ ] **Step 4: Bake the config template + a default `SOUL.md`** in the `Dockerfile`:

```dockerfile
COPY configs/config.yaml /opt/hermes-defaults/.hermes/config.yaml
RUN printf '# SOUL.md — Hermes persona\nYou are a helpful assistant running on a Linux desktop. Be concise.\n' \
      > /opt/hermes-defaults/.hermes/SOUL.md
```

- [ ] **Step 5: Replace the spike's inline config write in `entrypoint.sh`** with template seeding (the spike Task-4 block that did `cat > ~/.hermes/config.yaml <<YAML …`). Seed from template only if absent:

```bash
su - "$USER" -c 'mkdir -p ~/.hermes'
for f in config.yaml SOUL.md; do
  if [ ! -f "/home/$USER/.hermes/$f" ] && [ -f "/opt/hermes-defaults/.hermes/$f" ]; then
    cp "/opt/hermes-defaults/.hermes/$f" "/home/$USER/.hermes/$f"
  fi
done
chown -R "$USER:$USER" "/home/$USER/.hermes"
```

- [ ] **Step 6: Rebuild on clean volume + verify**

Run: `docker compose down -v && ./scripts/spike-up.sh && ./scripts/verify-config-seed.sh`
Expected: `[verify-config-seed] PASS`. Re-run `./scripts/verify-persistence.sh` and `./scripts/verify-gonogo.sh` → both still green.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(2a): seed ~/.hermes config.yaml + SOUL.md from template"
```

---

### Task 4: Computer-use E2E acceptance — automated harness + documented model-in-the-loop gate

**Files:**
- Create: `<repo>/scripts/verify-e2e.sh` (automated, no API key)
- Create: `<repo>/docs/E2E-ACCEPTANCE.md` (the credentialed manual procedure)

**Interfaces:**
- Consumes: everything from Tasks 1–3 (persistent, configured Hermes on a fresh volume).
- Produces: an automated fresh-volume regression gate + a documented manual acceptance that closes the spike's actuation-glue gap.

- [ ] **Step 1: Write `scripts/verify-e2e.sh` — the no-API-key fresh-volume regression**

```bash
#!/usr/bin/env bash
# Fresh named volume → full stack still GO, browser CDP attachable. No model key needed.
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[e2e] dropping volume + fresh boot…"
docker compose down -v >/dev/null 2>&1 || true
./scripts/spike-up.sh >/dev/null
echo "[e2e] go/no-go battery on the fresh volume"
./scripts/verify-gonogo.sh >/dev/null && echo "  OK battery GO" || { echo "  FAIL battery"; exit 1; }
echo "[e2e] config + persona seeded on this fresh volume"
docker exec "$C" su - "$U" -c 'test -f ~/.hermes/config.yaml && test -f ~/.hermes/SOUL.md' \
  && echo "  OK seeded" || { echo "  FAIL seed"; exit 1; }
echo "[e2e] launch visible Chrome on :1 + Hermes /browser connect attaches to :9222"
docker exec "$C" su - "$U" -c \
  'DISPLAY=:1 setsid google-chrome-stable --remote-debugging-port=9222 --user-data-dir=/tmp/e2e about:blank >/dev/null 2>&1 &' || true
sleep 4
docker exec "$C" bash -lc 'curl -fsS http://127.0.0.1:9222/json/version >/dev/null' \
  && echo "  OK CDP endpoint live (agent-browser /browser connect target)" || { echo "  FAIL CDP"; exit 1; }
echo "[e2e] PASS (automated; model-in-the-loop step is docs/E2E-ACCEPTANCE.md)"
```

> Note on `/browser connect`: driving it fully is a TUI/interactive command; this harness verifies the CDP endpoint Hermes would attach to is live on `:1`. The actual `/browser connect` + a model turn is in the manual doc (needs a key).

- [ ] **Step 2: Run it**

Run: `./scripts/verify-e2e.sh`
Expected: `[e2e] PASS`. This is the fresh-volume regression closing the volume-shadow gap.

- [ ] **Step 3: Write `docs/E2E-ACCEPTANCE.md` — the credentialed manual gate (closes the actuation-glue gap)**

Exact, copy-pasteable procedure (no placeholders):

````markdown
# Computer-Use E2E Acceptance (manual, needs a model API key)

Validates the one thing the automated suite can't: a model driving `computer_use`
to actually operate the XFCE desktop, observed live over NoVNC.

## 1. Bring up + set a model key
```bash
HERMES_USER=hermes HERMES_PASSWORD=hermes123 docker compose up -d
# Set ONE provider key (example: Anthropic). Or use `hermes setup` in the terminal.
docker exec -it hermes-desktop su - hermes -c \
  'echo "ANTHROPIC_API_KEY=sk-ant-…" >> ~/.hermes/.env'
docker exec -it hermes-desktop su - hermes -c \
  'hermes config set model anthropic/claude-sonnet-4-6'   # or set in `hermes model`
```

## 2. Watch the desktop
Open http://localhost:6080/vnc.html (password `hermes123`). Leave a window
(e.g. Mousepad) focused on `:1`.

## 3. Drive computer_use
```bash
docker exec -it hermes-desktop su - hermes -c 'DISPLAY=:1 hermes -t computer_use chat'
# In the TUI, prompt: "Open Mousepad if it isn't open, then type 'hello from hermes' into it."
```

## 4. Acceptance criteria
- Over NoVNC you SEE Mousepad receive the typed text (AT-SPI/XSendEvent actuation).
- (Optional browser leg) prompt: "/browser connect, then open example.com and read the H1."
  Expect `/browser connect` to attach to the Chrome on `:9222` and the agent to read the page.
- `docker compose down && docker compose up -d` → the session/config persist (named volume).

Record PASS/FAIL + notes here. A PASS closes the spike's deferred "model-in-the-loop"
and "fresh named volume" gaps and clears Phase 2A.
````

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(2a): computer-use E2E — automated fresh-volume gate + manual acceptance doc"
```

---

## Phase 2B / 2C (deferred)

After 2A is reviewed and the manual E2E acceptance is run with a key: **2B** ports the full remote-desktop shell (xRDP + RDP→`:1` libvnc convergence + raw VNC + wallpaper + Hermes Dashboard/Terminal/Setup shortcuts + fonts/locale + tini/s6 PID1, which also fixes the spike's bare-bash PID1). **2C** adds dashboard auto-start on 9119 (`0.0.0.0`+basic-auth, host-map `127.0.0.1`), image slimming (multi-stage; drop build-essential), pins Hermes to a release tag, suppresses the cosmetic cua systemd-unit warning, fixes the inert `.bashrc` env append, clears the remaining deferred Minors, and writes the README/Docker Hub overview.

## Self-Review

- **Spec coverage (2A scope):** named-volume persistence (design §"root-FHS / volume" + final-review volume-shadow gap) → Tasks 2; config/persona seeding (design Layer ②) → Task 3; env identity/validation (design Layer ① + decisions) → Task 1; model-in-the-loop + fresh-volume E2E (final-review recommendation) → Task 4. Dashboard/RDP/init/slimming/Minors are explicitly 2B/2C — deferred, not gaps.
- **Placeholder scan:** no "TBD"/"add error handling". Task 3 Step 1's "confirm schema against cli-config.yaml.example" is a concrete read-then-use instruction with the fallback (the spike's known-working `computer_use:` block) named — not hand-waving. The E2E doc has literal commands.
- **Type/name consistency:** container `hermes-desktop`, image `hermes-desktop:latest`, volume `hermes-home`, env `HERMES_USER`/`HERMES_PASSWORD`, resolved `$USER`/`$PASSWORD`, template `/opt/hermes-defaults`, seed marker `/home/$USER/.seeded`, cua marker `~/.hermes/.cua-installed` — used identically across tasks and scripts. Verify scripts renamed off `hermes-spike` in Task 1 Step 6 before later tasks rely on `hermes-desktop`.
- **Ordering risk:** Task 1's dynamic user creation + Task 2's first-boot seed both run before the VNC/AT-SPI/cua blocks; the seed's `chown -R` precedes those blocks' home writes. Confirmed compatible with `set -euo pipefail` (all new vars defined; `cp -an … || true` guarded).

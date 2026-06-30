# CI: verify-gate suite (amd64) + native-arm64 verification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions CI that runs the full `verify-*.sh` gate suite on every change (build-from-source, amd64) and verifies the published image on a native `ubuntu-24.04-arm` runner — locking in quality and resolving the open native-arm64 CDP risk.

**Architecture:** One reusable orchestrator `scripts/verify-all.sh` boots the stack through the existing `docker-compose.yml` (build mode, or pull-image mode when `IMG` is set) and runs the 17 `verify-*.sh` gates. Two focused workflow files call it: `ci-verify.yml` (amd64, build-from-source, on PR/push/dispatch) and `arm64-published-verify.yml` (native arm64, pull-image mode, weekly + dispatch, opens an issue on failure).

**Tech Stack:** GitHub Actions, Docker + Docker Compose v2, Bash, `gh` CLI (preinstalled on runners).

## Global Constraints

- **Zero secrets.** Build-from-source needs no registry; the arm64 job pulls a public image and files issues with the built-in `GITHUB_TOKEN`. Copied from spec §2.
- **Action pinning:** third-party actions pinned to a commit SHA with a `# vX` comment; first-party `actions/checkout` stays at `@v4` (matches the existing `dockerhub-description.yml`).
- **Workflow header comments:** each workflow file opens with a comment documenting its triggers, runner, and that it needs no secrets.
- **Fixed identifiers:** image repo `neoplanetz/hermes-desktop-docker`; default verified tag `1.1.0`; container name `hermes-desktop`; `docker-compose.yml` lives at the repo root.
- **Runners:** amd64 = `ubuntu-latest`; arm64 = `ubuntu-24.04-arm` (GitHub-hosted native arm64, free for public repos).
- **⚠️ The suite is volume-destructive.** `verify-persistence.sh` recreates the container and `verify-e2e.sh` runs `docker compose down -v`; `verify-all.sh` also tears down with `down -v`. This wipes the `hermes-home` named volume (any live `~/.hermes` state — Nous token, config). Safe on ephemeral CI runners; **destructive if run locally against a live desktop.**

---

### Task 1: `scripts/verify-all.sh` gate orchestrator

**Files:**
- Create: `scripts/verify-all.sh`

**Interfaces:**
- Consumes: the existing `scripts/verify-*.sh` gates (each exits non-zero on failure) and `docker-compose.yml` at the repo root (service `hermes-desktop`, healthcheck, named volume `hermes-home`).
- Produces: an executable `scripts/verify-all.sh` that exits `0` only when every gate passes. Modes: **build** (default — `docker compose up -d --build`) and **pull-image** (`IMG` set — `docker pull "$IMG"; docker tag "$IMG" hermes-desktop:latest; docker compose up -d --no-build`). In pull-image mode it runs 16 gates (skips `verify-e2e`, which rebuilds from source). Later tasks invoke it as `./scripts/verify-all.sh` (amd64) and `IMG=neoplanetz/hermes-desktop-docker:1.1.0 ./scripts/verify-all.sh` (arm64).

- [ ] **Step 1: Write `scripts/verify-all.sh`**

```bash
#!/usr/bin/env bash
# Run the full verify-*.sh gate suite against a hermes-desktop container.
#
# Modes:
#   build mode  (default)  : docker compose up -d --build          (amd64 CI + local dev)
#   pull-image  (IMG set)  : docker pull "$IMG"; tag hermes-desktop:latest;
#                            docker compose up -d --no-build        (arm64 CI: verify the
#                            PUBLISHED image on real hardware — the only place arm64 CDP
#                            Chrome runs, since local QEMU emulation core-dumps it)
#
# Usage:
#   scripts/verify-all.sh                                            # build from source
#   IMG=neoplanetz/hermes-desktop-docker:1.1.0 scripts/verify-all.sh # pull + verify
#
# ⚠️ DESTRUCTIVE: tears down with `docker compose down -v`, wiping the hermes-home
# volume (verify-e2e/-persistence already do). Safe on ephemeral CI runners; do NOT
# run against a live local desktop you care about without backing up ~/.hermes first.
#
# Exits non-zero on the first failing gate, naming it.
set -uo pipefail
cd "$(dirname "$0")/.."

C=hermes-desktop
IMG="${IMG:-}"
MODE="build"; [ -n "$IMG" ] && MODE="pull-image"
echo "[verify-all] mode=$MODE${IMG:+ image=$IMG}"

# ---- boot ----------------------------------------------------------------
if [ "$MODE" = "pull-image" ]; then
  echo "[verify-all] pulling $IMG -> tagging hermes-desktop:latest"
  docker pull "$IMG"
  docker tag "$IMG" hermes-desktop:latest
  docker compose up -d --no-build
else
  echo "[verify-all] building image from source"
  docker compose up -d --build
fi

# ---- wait for the compose healthcheck to report healthy ------------------
echo "[verify-all] waiting for container health (compose start_period is 90s)..."
deadline=$((SECONDS + 300))
while :; do
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$C" 2>/dev/null || echo missing)
  case "$status" in
    healthy) echo "[verify-all]   healthy (+${SECONDS}s)"; break ;;
    missing) echo "[verify-all]   FAIL: container $C not found"; docker compose logs --tail 50 || true; exit 1 ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "[verify-all]   FAIL: not healthy within 300s (last status=$status)"
    docker inspect -f '{{json .State.Health}}' "$C" 2>/dev/null || true
    docker compose logs --tail 50 || true
    exit 1
  fi
  sleep 5
done

# ---- run the gates -------------------------------------------------------
# Ordering rules:
#  - verify-cdp BEFORE verify-gonogo/verify-e2e: gonogo/e2e launch extra Chromes on
#    :9222; verify-cdp asserts the autostarted CDP is loopback-only, so it must see
#    only that one.
#  - verify-persistence near the end: it `docker compose up -d --force-recreate`
#    (keeps the volume; no rebuild because hermes-desktop:latest is already present).
#  - verify-e2e LAST and BUILD MODE ONLY: it `docker compose down -v` (wipes the
#    volume) and re-boots via spike-up.sh which `docker compose build`s from source,
#    so it cannot verify a *pulled* image. Native-arm64 CDP is already covered by
#    verify-cdp + verify-gonogo above.
GATES=(identity init desktop rdp rdp-converge cdp gonogo dashboard
       config-seed quiet-boot hermes desktop-shortcuts env-clean slim docs
       persistence)

failed=""
for g in "${GATES[@]}"; do
  echo; echo "===== verify-$g ====="
  if ! ./scripts/verify-"$g".sh; then failed="$g"; break; fi
done

if [ -z "$failed" ]; then
  if [ "$MODE" = "build" ]; then
    echo; echo "===== verify-e2e ====="
    ./scripts/verify-e2e.sh || failed="e2e"
  else
    echo; echo "[verify-all] SKIP verify-e2e in pull-image mode (it rebuilds from"
    echo "             source via spike-up.sh, so it can't verify the pulled image)."
  fi
fi

# ---- teardown ------------------------------------------------------------
echo; echo "[verify-all] tearing down (docker compose down -v)"
docker compose down -v >/dev/null 2>&1 || true

if [ -n "$failed" ]; then
  echo "[verify-all] FAIL at gate: verify-$failed"
  exit 1
fi
echo "[verify-all] ALL GATES PASS (mode=$MODE)"
```

- [ ] **Step 2: Syntax-check and make executable**

Run:
```bash
bash -n scripts/verify-all.sh && chmod +x scripts/verify-all.sh && echo OK
```
Expected: `OK` (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-all.sh
git commit -m "ci: add verify-all.sh gate orchestrator (build + pull-image modes)"
```

> **Functional validation is deferred to CI (Tasks 2–3), on purpose.** A full local run builds the ~6 GB image and then `down -v` wipes the `hermes-home` volume — destructive to any live local desktop. The orchestrator is exercised end-to-end by the `ci-verify.yml` dispatch (build mode) and `arm64-published-verify.yml` dispatch (pull-image mode) on ephemeral runners. If you *do* want a local run first, back up `~/.hermes` (or accept re-running `hermes setup`) and run `./scripts/verify-all.sh`, expecting a final `[verify-all] ALL GATES PASS (mode=build)`.

---

### Task 2: `.github/workflows/ci-verify.yml` (amd64 gate suite)

**Files:**
- Create: `.github/workflows/ci-verify.yml`

**Interfaces:**
- Consumes: `scripts/verify-all.sh` (Task 1), run in build mode.
- Produces: a workflow named `CI (verify gates, amd64)` triggered on `pull_request`→main, `push`→main, and `workflow_dispatch`.

- [ ] **Step 1: Write `.github/workflows/ci-verify.yml`**

```yaml
# CI: build the image from source and run the full verify-*.sh gate suite (amd64).
#
# Triggers: pull_request -> main, push -> main, manual (workflow_dispatch)
# Runner:   ubuntu-latest (amd64)
# Secrets:  none (build-from-source; no registry, no push)
#
# The ~6 GB image build dominates runtime; a cold build is acceptable at this
# repo's PR volume (build caching is an optional optimization, see
# docs/superpowers/specs/2026-06-30-ci-verify-arm64-design.md).
name: CI (verify gates, amd64)

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run full verify-gate suite (build mode)
        run: ./scripts/verify-all.sh

      - name: Tear down (always)
        if: always()
        run: docker compose down -v || true
```

- [ ] **Step 2: Validate YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci-verify.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci-verify.yml
git commit -m "ci: add amd64 verify-gate workflow (PR/push/dispatch)"
```

- [ ] **Step 4: Acceptance — dispatch on GitHub (after push)**

Run (once the branch is pushed):
```bash
gh workflow run "CI (verify gates, amd64)" && sleep 5 && gh run list --workflow="CI (verify gates, amd64)" --limit 1
```
Then watch:
```bash
gh run watch "$(gh run list --workflow='CI (verify gates, amd64)' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: the run builds the image and ends green with `[verify-all] ALL GATES PASS (mode=build)` in the step log. This is the end-to-end functional test of `verify-all.sh` build mode.

---

### Task 3: `.github/workflows/arm64-published-verify.yml` (native arm64)

**Files:**
- Create: `.github/workflows/arm64-published-verify.yml`

**Interfaces:**
- Consumes: `scripts/verify-all.sh` (Task 1), run in pull-image mode (`IMG` set).
- Produces: a workflow named `Verify published image (native arm64)` triggered weekly (Mon 06:00 UTC) and on `workflow_dispatch` (with a `tag` input defaulting to `1.1.0`); opens a GitHub issue on failure.

- [ ] **Step 1: Write `.github/workflows/arm64-published-verify.yml`**

```yaml
# Native-arm64 verification of the PUBLISHED image.
#
# Pulls the published multi-arch image on a native arm64 runner and runs the full
# verify-*.sh gate suite (pull-image mode) — the one environment that actually
# exercises arm64 CDP Chrome (local QEMU emulation core-dumps it). Resolves the open
# "native-arm64 CDP unverified" risk.
#
# Triggers: weekly schedule (Mon 06:00 UTC), manual (workflow_dispatch w/ tag input)
# Runner:   ubuntu-24.04-arm (GitHub-hosted native arm64, free for public repos)
# Secrets:  none (public image pull; GITHUB_TOKEN files the issue on failure)
name: Verify published image (native arm64)

on:
  schedule:
    - cron: '0 6 * * 1'   # Mondays 06:00 UTC
  workflow_dispatch:
    inputs:
      tag:
        description: 'Published image tag to verify'
        default: '1.1.0'
        required: false

permissions:
  contents: read
  issues: write

env:
  IMAGE: neoplanetz/hermes-desktop-docker

jobs:
  verify-arm64:
    runs-on: ubuntu-24.04-arm
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Resolve tag
        id: tag
        run: echo "tag=${{ github.event.inputs.tag || '1.1.0' }}" >> "$GITHUB_OUTPUT"

      - name: Verify published arm64 image (pull-image mode)
        run: IMG="${IMAGE}:${{ steps.tag.outputs.tag }}" ./scripts/verify-all.sh

      - name: Tear down (always)
        if: always()
        run: docker compose down -v || true

      - name: Open an issue on failure
        if: failure()
        env:
          GH_TOKEN: ${{ github.token }}
          IMG_REF: ${{ env.IMAGE }}:${{ steps.tag.outputs.tag }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          gh issue create \
            --title "native-arm64 verification failed (${IMG_REF})" \
            --body "A native-arm64 gate run failed while verifying the published image \`${IMG_REF}\` on a real \`ubuntu-24.04-arm\` runner. See the failing gate in the run log: ${RUN_URL}"
```

- [ ] **Step 2: Validate YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/arm64-published-verify.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/arm64-published-verify.yml
git commit -m "ci: add native-arm64 published-image verification (weekly + dispatch)"
```

- [ ] **Step 4: Acceptance — dispatch on GitHub (after push)**

Run (once the branch is pushed):
```bash
gh workflow run "Verify published image (native arm64)" -f tag=1.1.0
sleep 5
gh run watch "$(gh run list --workflow='Verify published image (native arm64)' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: a native arm64 run that pulls `neoplanetz/hermes-desktop-docker:1.1.0`, boots it, and ends green having run 16 gates (e2e skipped) — **including a real native-arm64 CDP result** (verify-cdp + verify-gonogo), the previously unverifiable leg. To confirm the failure path opens an issue, dispatch once against a known-bad tag (e.g. `-f tag=does-not-exist`) and check `gh issue list`.

---

## Notes / assumptions to confirm on first dispatch

- GitHub-hosted `ubuntu-24.04-arm` runners ship Docker + Compose v2 (same as `ubuntu-latest`). If a run reports `docker: command not found`, add a Docker setup step.
- Runner disk (~14 GB on `/`) holds the ~6 GB image build (amd64) and the pulled image (arm64). If a build runs out of space, add a free-disk step (e.g. prune the runner's preinstalled toolcache).
- In pull-image mode, `verify-persistence.sh`'s internal `docker compose up -d --force-recreate` reuses the pulled `hermes-desktop:latest` (image present → no rebuild), so it still verifies the pulled image.

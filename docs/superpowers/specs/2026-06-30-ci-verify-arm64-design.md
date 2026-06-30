# CI: verify-gate suite (amd64) + native-arm64 published-image verification

- **Date:** 2026-06-30
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

The image is published publicly and has converged through three Codex review rounds
behind a 17-gate `scripts/verify-*.sh` suite that is currently run **by hand on a local
amd64 host**. Two gaps remain:

1. **No automation.** Nothing re-runs the gates on a change, so a regression in
   `Dockerfile` / `entrypoint.sh` / `scripts/` can land silently — the quality the
   review rounds bought is not locked in.
2. **Native-arm64 CDP is unverified.** The published multi-arch image advertises
   `linux/arm64`, but its arm64 variant was built under QEMU cross-emulation and has
   never run on real arm64 hardware. Locally this is unverifiable: QEMU user-mode
   emulation core-dumps the CDP Chrome (a V8/JIT emulation limit), while the same image
   is stable on amd64. So the load-bearing "arm64 works" claim rests on an untested
   artifact.

**Decision:** add GitHub Actions CI that (a) runs the full gate suite on every change
(build-from-source, amd64), and (b) verifies the **published** arm64 image on a
**native `ubuntu-24.04-arm` runner** (free for public repos) — the one environment that
can actually exercise arm64 CDP. This locks in quality *and* resolves the open risk.

## 2. Goals (in scope)

- **Automated gate suite (amd64).** On PR→main, push→main, and manual dispatch: build
  the image from source and run all 17 `verify-*.sh` gates against it.
- **Native-arm64 verification of the published image.** On a weekly schedule and manual
  dispatch: pull the published multi-arch image on a native arm64 runner and run the same
  17 gates. On failure, auto-open a GitHub issue.
- **One reusable orchestrator.** A single `scripts/verify-all.sh` that runs the whole
  suite — usable locally and by both CI jobs — with a build mode and a pull-image mode.
- **Zero secrets.** Build-from-source needs no registry; the arm64 job pulls a public
  image and files issues with the built-in `GITHUB_TOKEN`.

## 3. Non-goals (YAGNI)

- **Automated multi-arch build/publish.** Image build + push stays the manual
  `docker buildx imagetools` flow (chosen earlier). CI verifies; it does not release.
- **Per-PR arm64 builds.** The arm64 job verifies the *published* artifact, not PR
  source, so it does not run on PRs. (Per-PR arm64 source-build gating was explicitly
  declined as too costly for a low-traffic repo.)
- **Branch-protection / required checks.** Enforcing "gates must pass before merge" is a
  repository setting, outside the workflow. Documented as an optional follow-up.

## 4. Architecture

Three pieces: one orchestrator script + two workflow files (one focused workflow per
concern, matching the existing `dockerhub-description.yml` convention).

### 4.1 `scripts/verify-all.sh` — gate orchestrator (new; local + CI)

Runs the full suite in one command. Two modes selected by env:

- **build mode** (default; amd64 CI + local dev): `docker compose up -d --build`.
- **pull-image mode** (arm64 CI): when `IMG` is set —
  `docker pull "$IMG" && docker tag "$IMG" hermes-desktop:latest && docker compose up -d --no-build`.

Both modes boot through the **existing `docker-compose.yml`** (container `hermes-desktop`,
loopback ports, `shm_size 2gb`, `init`, healthcheck, named volume), so the
`docker exec`-based gates run identically regardless of architecture or image source —
only the image's origin differs.

Flow:
1. Boot (build or pull-image mode).
2. Poll `docker inspect` health until `healthy` (compose `start_period` is 90s; allow ~5 min).
3. Run the runtime gates against the running container in order: identity, init, desktop,
   rdp, rdp-converge, cdp, gonogo, dashboard, config-seed, quiet-boot, hermes,
   desktop-shortcuts, env-clean; plus the image/repo gates slim and docs.
4. **persistence** gate requires a container **recreate**: write a probe, `docker compose
   down` (keep the volume), `up -d`, re-wait healthy, then assert the probe survived.
5. Tear down the main run: `docker compose down -v`.
6. **e2e** gate runs last, against a fresh-volume cold boot. The plan confirms whether it
   manages its own container lifecycle or the orchestrator hands it a clean recreate;
   either way it runs after step 5 so it never shares state with the gates above.
7. Final safety cleanup: ensure no `hermes-desktop` container or `hermes-home` volume is
   left behind.
8. Exit non-zero on the first gate failure, naming the gate, so CI surfaces what broke.

(Exact sequencing of the two lifecycle-sensitive gates — persistence recreate, e2e
fresh-volume — is finalized in the implementation plan against each script's actual
behavior. The 17 gates are the current `scripts/verify-*.sh` set: cdp, config-seed,
dashboard, desktop, desktop-shortcuts, docs, e2e, env-clean, gonogo, hermes, identity,
init, persistence, quiet-boot, rdp, rdp-converge, slim.)

### 4.2 `.github/workflows/ci-verify.yml` — amd64 gate suite

- **Triggers:** `pull_request` (base `main`), `push` (`main`), `workflow_dispatch`.
- **Runner:** `ubuntu-latest`.
- **Steps:** checkout → run `scripts/verify-all.sh` (build mode) → always tear down.
  Build caching (buildx + a GHA cache feeding the compose build) is a plan-level
  optimization; a cold ~6 GB build is acceptable at this repo's PR volume, so caching is
  optional, not load-bearing.
- **Permissions:** `contents: read`. No secrets.
- **Note:** the ~6 GB image build dominates runtime; runner disk (~14 GB on `/`) is
  adequate but tight — the plan frees space / prunes if the build needs headroom.

### 4.3 `.github/workflows/arm64-published-verify.yml` — native arm64

- **Triggers:** `schedule` (weekly) + `workflow_dispatch`.
- **Runner:** `ubuntu-24.04-arm` (GitHub-hosted native arm64, free for public repos).
- **Steps:** checkout → `IMG=neoplanetz/hermes-desktop-docker:1.1.0 scripts/verify-all.sh`
  (pull-image mode → native boot → 17 gates) → on `failure()`, `gh issue create`
  summarizing the failed run (which gate, run URL) → always tear down.
- The verified image tag is a workflow `env` var (default `:1.1.0`) so a version bump
  touches one line.
- **Permissions:** `contents: read` + `issues: write`. No secrets (public pull;
  `GITHUB_TOKEN` for the issue).

## 5. Conventions / guardrails

- Third-party actions pinned to a commit SHA with a `# vX` comment (matches
  `dockerhub-description.yml`). Issue creation uses the preinstalled `gh` CLI rather than
  a third-party action, minimizing pinned dependencies.
- Each workflow file opens with a header comment documenting its triggers, runner, and
  that it needs no secrets.
- The released image tag is centralized in one variable.

## 6. Verification (how we know the CI itself works)

- `scripts/verify-all.sh` runs green locally in build mode (parity with the manual
  sequence) before any CI wiring.
- `ci-verify.yml`: dispatch / open a PR → the run builds and reports all 17 gates green;
  introduce a deliberate breakage → the run goes red on the right gate.
- `arm64-published-verify.yml`: `workflow_dispatch` → the native arm64 run pulls the
  published image and reports the 17 gates, **including a real native-arm64 CDP result**
  (the previously unverifiable leg); force a failure → an issue is opened.

## 7. Defaults (adjustable in the plan)

- **Weekly schedule:** Monday 06:00 UTC (a low-traffic slot).
- **Verified image tag:** `:1.1.0` (the current release; `:latest` is an alternative).

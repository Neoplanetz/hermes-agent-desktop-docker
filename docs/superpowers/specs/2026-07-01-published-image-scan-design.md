# Scheduled Trivy scan of the published image

- **Date:** 2026-07-01
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

The PR/push CI gains a Trivy scan (`scripts/scan-image.sh` in `ci-verify.yml`) that
scans the image **built from current source** and fails on a fixable CRITICAL. That
catches vulnerabilities in *changes*. It does not catch the other half: **CVEs disclosed
*after* release, in the unchanged artifact users actually pull.** Because publishing is a
manual `docker buildx` flow, `main` can move ahead of the published tags — so the image on
Docker Hub can carry a fixable CRITICAL that current source no longer has, and nothing
watches it.

**Decision:** add a scheduled workflow that pulls the **published** image and Trivy-scans
it on a weekly cadence, **opening a GitHub issue** when it finds a CRITICAL with a fix
available — an actionable "rebuild + republish" alert. It reuses `scripts/scan-image.sh`
and mirrors the existing `arm64-published-verify.yml` shape (weekly cron + dispatch +
issue-on-failure).

## 2. Goals (in scope)

- **Scan the published image on a schedule.** Weekly + manual dispatch: run
  `scripts/scan-image.sh <IMAGE>:<tag>` against the published Docker Hub image (Trivy pulls
  the remote ref itself).
- **Alert via a GitHub issue** when the reused gate fails (a fixable CRITICAL in the
  published artifact) — issue body names the offending CVE(s) + links the run.
- **De-duplicate** issues: if an open issue with the workflow's label already exists, do not
  open another (a persistent, un-republished CVE must not spawn a weekly pile of issues).
- **Reuse, don't duplicate:** the same `scripts/scan-image.sh` and pinned Trivy setup the
  PR scan uses; the same trigger/issue shape as `arm64-published-verify.yml`.
- **Zero secrets.** Public image pull; the built-in `GITHUB_TOKEN` files the issue.

## 3. Non-goals (YAGNI)

- **No SARIF upload to code scanning.** Issue-only (chosen). The source scan already
  populates the Security tab; the published-image's unique value is the actionable
  republish alert. (SARIF with a distinct `category` could be layered later.)
- **No arm64-variant scan.** Scan the amd64 platform (the runner default). amd64 and arm64
  share the OS package set; the arm64 Chromium-vs-Chrome delta is not worth a second scan.
- **No auto-rebuild/republish.** Image build + push stays the manual `buildx` flow; this
  workflow alerts, it does not release.
- **No HIGH gating.** The reused gate fires on fixable CRITICAL only (unchanged
  `scripts/scan-image.sh`).
- **No new script.** `scripts/scan-image.sh` already scans an image ref and gates; it is
  reused verbatim.

## 4. Architecture

One new workflow file: `.github/workflows/published-image-scan.yml`. No script changes.

- **Triggers:** `schedule` (weekly) + `workflow_dispatch` with an optional `tag` input
  (blank → the `TAG` env default), matching `arm64-published-verify.yml`.
- **Runner:** `ubuntu-latest`.
- **Env:** `IMAGE: neoplanetz/hermes-desktop-docker`, `TAG: 'latest'` (the floating tag a
  default `docker pull` gets — the artifact whose drift we care about; dispatch overrides).
- **Permissions:** `contents: read` + `issues: write`. No secrets.
- **Steps:**
  1. Checkout (to get `scripts/scan-image.sh`).
  2. Install Trivy — pinned `aquasecurity/setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1`, `version: v0.72.0`.
  3. Resolve tag (input or `TAG`).
  4. **Scan** — `./scripts/scan-image.sh "$IMAGE:$tag"`, capturing stdout to a log
     (`… | tee "$RUNNER_TEMP/scan.log"` under `set -o pipefail`, so the step's exit code is
     the gate's). Trivy pulls the remote image, scans (`--scanners vuln`), and the script
     exits non-zero on a fixable CRITICAL, printing the offending `CVE / pkg / installed /
     fixed` lines.
  5. **On failure** (`if: failure()`): de-dup, then open an issue. Query
     `gh issue list --label published-image-scan --state open`; if one exists, skip (leave a
     `log()`-style note); else `gh issue create --label published-image-scan` with a title
     naming the image ref and a body containing the captured fixable-CRITICAL lines (grepped
     from `scan.log`) + the run URL + a one-line "rebuild & republish" pointer.
- **Header comment** documents triggers, runner, that it reuses `scripts/scan-image.sh`, and
  that it needs no secrets — matching the other workflow files.

### 4.1 Why reuse holds

`scripts/scan-image.sh` runs `trivy image --scanners vuln … "$IMG"`. `trivy image` accepts a
**remote registry reference** and pulls it itself — no `docker pull`/Docker daemon step
needed. So `./scripts/scan-image.sh neoplanetz/hermes-desktop-docker:latest` scans the
published image exactly as the PR scan scans the local build, and gates identically.

## 5. Error / edge behavior

- **Trivy DB or registry pull hiccup** → the scan step errors (not the gate) → the job fails
  → the issue step fires. To avoid a false "CVE found" issue on infra flakiness, the issue
  body distinguishes gate-failure from scan-error by grepping `scan.log` for the
  `[scan-image] FAIL:` marker; if absent, the issue notes a scan/infra error instead of a
  CVE list. (Both still warrant a look, so both open an issue — de-duped by label.)
- **Persistent CVE across weeks** → the label de-dup keeps exactly one open issue until it is
  closed (after republish).
- **Clean scan** → the job passes, no issue.

## 6. Conventions / guardrails

- Third-party action pinned by SHA + `# vX` (`aquasecurity/setup-trivy`); issue creation via
  the preinstalled `gh` CLI (no extra pinned action) — matches `arm64-published-verify.yml`.
- The image repo + default tag are single-source `env` vars (one line to bump).
- Issue label `published-image-scan` is the de-dup key and is created if missing.

## 7. Verification (how we know it works)

- `workflow_dispatch` → the run pulls `neoplanetz/hermes-desktop-docker:latest`, scans it,
  and either passes (no fixable CRITICAL) or opens one labelled issue.
- Force the failure path: dispatch with `tag` set to a deliberately old/vulnerable tag (or
  temporarily point at an image known to have a fixable CRITICAL) → confirm exactly one
  `published-image-scan`-labelled issue opens, with the CVE lines + run URL; re-dispatch →
  confirm the de-dup skips a second issue.
- Confirm a clean current scan does **not** open an issue.

## 8. Defaults (adjustable in the plan)

- **Schedule:** Thursday 06:00 UTC (`0 6 * * 4`) — spread across the week from the Monday
  arm64 job.
- **Default tag:** `latest`.
- **Issue label:** `published-image-scan`.

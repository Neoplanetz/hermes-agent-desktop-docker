# Trivy image vulnerability scan — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan the CI-built image with Trivy on every PR/push — upload all findings to GitHub code scanning (SARIF) and fail CI only on CRITICAL vulnerabilities that have a fix available.

**Architecture:** A single runnable script `scripts/scan-image.sh` scans the already-built `hermes-desktop:latest` **once** (`trivy image --format json`), then derives two outputs from that one JSON: a SARIF report (`trivy convert`, all severities, non-blocking) and a `jq`-based gate (exit 1 iff a CRITICAL vuln has a `FixedVersion`). The existing `ci-verify.yml` `verify` job gains steps to install Trivy, run the script against the image its build step already produced (`docker compose down -v` does not remove the image), and upload the SARIF — plus `security-events: write` permission.

**Tech Stack:** GitHub Actions, Trivy (CLI via `aquasecurity/setup-trivy`), `jq`, Bash, Docker.

## Global Constraints

- **Scope: vulnerability scanning only** (`trivy --scanners vuln`). No SBOM, no cosign signing, no scheduled published-image scan. Copied from spec §2/§3.
- **Gating:** report **all severities** via SARIF (non-blocking); fail CI **only on CRITICAL with a fix available**. Copied from spec §5.
- **Reuse the existing build.** No second image build; scan the `hermes-desktop:latest` the verify step already produced. Copied from spec §3/§4.1.
- **Action pinning (repo convention):** first-party (`actions/*`, `github/*`) by version tag (`actions/checkout@v7`, `github/codeql-action/upload-sarif@v3`); third-party (`aquasecurity/setup-trivy`) by **commit SHA + `# vX` comment** (`@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1`). Both Dependabot-tracked. Copied from spec §6.
- **Pinned Trivy CLI version:** `v0.72.0` (via `setup-trivy`'s `version:` input); the vuln DB still refreshes at run time.
- **Fork/Dependabot PRs run read-only** → the SARIF upload is best-effort (`continue-on-error: true`); `push`→`main` is the code-scanning source of truth. Copied from spec §4.3.
- **Fixed identifiers:** image `hermes-desktop:latest`; workflow `.github/workflows/ci-verify.yml`; SARIF artifact `trivy.sarif`; scan script `scripts/scan-image.sh`.
- **⚠️ Pushing `.github/workflows/*` needs the gh token `workflow` scope** (absent in this environment per project memory). Run `gh auth refresh -s workflow` before `git push`, or the push is rejected. Only affects Task 2's acceptance step.
- **Verified environment facts (2026-07-01):** CodeQL default setup = `not-configured`, so third-party `upload-sarif` uploads without conflict; `jq` is preinstalled on `ubuntu-latest`.

---

### Task 1: `scripts/scan-image.sh` — scan + SARIF + fixable-CRITICAL gate

**Files:**
- Create: `scripts/scan-image.sh`

**Interfaces:**
- Consumes: a locally-present image ref (default `hermes-desktop:latest`); the tools `trivy` and `jq`.
- Produces: an executable `scripts/scan-image.sh [IMAGE_REF]` that writes `$SARIF_OUT` (default `trivy.sarif`) and `$JSON_OUT` (default `trivy.json`), exits `0` when no CRITICAL vuln has a fix, and exits `1` (printing the offending vulns) when one does. Task 2 invokes it as `./scripts/scan-image.sh hermes-desktop:latest`.

- [ ] **Step 1: Write `scripts/scan-image.sh`**

```bash
#!/usr/bin/env bash
# Scan a built image for vulnerabilities with Trivy, emit SARIF for GitHub code
# scanning, and gate on fixable CRITICALs.
#
# Usage:
#   scripts/scan-image.sh [IMAGE_REF]     # default IMAGE_REF: hermes-desktop:latest
# Env (optional):
#   JSON_OUT   trivy JSON path   (default: trivy.json)
#   SARIF_OUT  SARIF output path (default: trivy.sarif)   <- the workflow uploads this
#
# One scan, two outputs (never scans the 6 GB image twice):
#   1. trivy image --scanners vuln --format json  -> $JSON_OUT   (all severities)
#   2. trivy convert --format sarif               -> $SARIF_OUT  (report, non-blocking)
#   3. jq gate over $JSON_OUT: exit 1 iff a CRITICAL vuln has a FixedVersion
#      (i.e. an actionable fix exists). Unfixable OS CVEs never fail the gate.
#
# Requires: trivy, jq (both present on GitHub runners; jq is standard on Linux).
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-hermes-desktop:latest}"
JSON_OUT="${JSON_OUT:-trivy.json}"
SARIF_OUT="${SARIF_OUT:-trivy.sarif}"

echo "[scan-image] scanning $IMG (vuln only) -> $JSON_OUT"
trivy image --scanners vuln --format json --output "$JSON_OUT" "$IMG"

echo "[scan-image] deriving SARIF (all severities) -> $SARIF_OUT"
trivy convert --format sarif --output "$SARIF_OUT" "$JSON_OUT"

echo "[scan-image] gate: CRITICAL vulns that have a fix available"
hits=$(jq -r '
  .Results[]?.Vulnerabilities[]?
  | select(.Severity == "CRITICAL" and (.FixedVersion // "") != "")
  | "\(.VulnerabilityID)\t\(.PkgName)\tinstalled=\(.InstalledVersion)\tfixed=\(.FixedVersion)"
' "$JSON_OUT")

count=$(printf '%s' "$hits" | grep -c . || true)
if [ "$count" -gt 0 ]; then
  echo "[scan-image] FAIL: $count fixable CRITICAL vuln(s):"
  printf '%s\n' "$hits" | sed 's/^/  /'
  echo "[scan-image] Remediate: bump the package in the Dockerfile, or add a justified"
  echo "             .trivyignore entry (CVE id + one-line reason + date). See plan Task 3."
  exit 1
fi
echo "[scan-image] PASS: no fixable CRITICAL vulns (SARIF written to $SARIF_OUT)"
```

- [ ] **Step 2: Syntax-check and make executable**

Run:
```bash
bash -n scripts/scan-image.sh && chmod +x scripts/scan-image.sh && echo OK
```
Expected: `OK` (no syntax errors).

- [ ] **Step 3 (OPTIONAL local smoke — needs `trivy` + network): confirm the plumbing on a tiny image**

Only if you have Trivy locally (install: `curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /tmp/trivy-bin v0.72.0 && export PATH=/tmp/trivy-bin:$PATH`). This validates the JSON→SARIF→jq wiring **without** the 6 GB build:
```bash
docker pull alpine:3.14
./scripts/scan-image.sh alpine:3.14; echo "exit=$?"
ls -l trivy.sarif && jq '.runs[0].tool.driver.name' trivy.sarif
```
Expected: `trivy.sarif` exists and reports `"Trivy"`; the script prints either `PASS` (exit 0) or `FAIL: N fixable CRITICAL` (exit 1). **Either exit proves the plumbing** — a red exit just means that old Alpine has a fixable CRITICAL. The authoritative run against the real image happens in CI (Task 2). Clean up: `rm -f trivy.json trivy.sarif`.

- [ ] **Step 4: Commit**

```bash
git add scripts/scan-image.sh
git commit -m "ci: add scan-image.sh (Trivy scan -> SARIF + fixable-CRITICAL gate)"
```

---

### Task 2: Wire the scan into `.github/workflows/ci-verify.yml`

**Files:**
- Modify: `.github/workflows/ci-verify.yml` (add `security-events: write`; add install/scan/upload steps after the existing verify step)

**Interfaces:**
- Consumes: `scripts/scan-image.sh` (Task 1); the `hermes-desktop:latest` image left by the existing "Run full verify-gate suite" step.
- Produces: the same `CI (verify gates, amd64)` workflow, now also installing Trivy, running the scan+gate, and uploading `trivy.sarif` to code scanning.

- [ ] **Step 1: Replace `.github/workflows/ci-verify.yml` with the full content below**

The change vs. today: header comment updated, `permissions:` gains `security-events: write`, and four steps are inserted between "Run full verify-gate suite" and "Tear down". `actions/checkout@v7` is unchanged.

```yaml
# CI: build the image from source and run the full verify-*.sh gate suite (amd64),
# then scan the built image for vulnerabilities with Trivy.
#
# Triggers: pull_request -> main, push -> main, manual (workflow_dispatch)
# Runner:   ubuntu-latest (amd64)
# Secrets:  none (build-from-source; no registry, no push)
# Perms:    contents:read + security-events:write (upload the Trivy SARIF to code
#           scanning). Fork/Dependabot PRs run read-only, so the SARIF upload is
#           best-effort (continue-on-error); push->main is the code-scanning source
#           of truth. See docs/superpowers/specs/2026-07-01-image-security-scan-design.md.
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
  security-events: write

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Run full verify-gate suite (build mode)
        run: ./scripts/verify-all.sh

      - name: Check image was built
        id: img
        if: always()
        run: |
          if docker image inspect hermes-desktop:latest >/dev/null 2>&1; then
            echo "built=true" >> "$GITHUB_OUTPUT"
          else
            echo "built=false" >> "$GITHUB_OUTPUT"
            echo "image hermes-desktop:latest absent (build failed); skipping scan"
          fi

      - name: Install Trivy
        if: always() && steps.img.outputs.built == 'true'
        uses: aquasecurity/setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1
        with:
          version: v0.72.0

      - name: Scan image + gate on fixable CRITICAL
        if: always() && steps.img.outputs.built == 'true'
        run: ./scripts/scan-image.sh hermes-desktop:latest

      - name: Upload Trivy SARIF to code scanning
        if: always() && steps.img.outputs.built == 'true'
        continue-on-error: true   # fork/Dependabot PRs are read-only; push->main is authoritative
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy.sarif

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
git commit -m "ci: scan the built image with Trivy and upload SARIF to code scanning"
```

- [ ] **Step 4: Acceptance — push + dispatch on GitHub**

Pushing workflow files needs the `workflow` token scope (see Global Constraints):
```bash
gh auth refresh -s workflow   # only if the push is rejected for missing 'workflow' scope
git push -u origin ci-trivy-image-scan
gh workflow run "CI (verify gates, amd64)" --ref ci-trivy-image-scan
sleep 5
gh run watch "$(gh run list --workflow='CI (verify gates, amd64)' --branch ci-trivy-image-scan --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: the run builds the image, runs the gates, then the **Scan image** step prints `[scan-image] PASS` (or `FAIL: N fixable CRITICAL …` → go to Task 3), and the **Upload Trivy SARIF** step succeeds. Confirm results landed:
```bash
gh api "repos/Neoplanetz/hermes-agent-desktop-docker/code-scanning/analyses?ref=refs/heads/ci-trivy-image-scan" --jq '.[0] | {tool: .tool.name, results: .results_count, ref: .ref}'
```
Expected: one analysis with `tool: "Trivy"` and a non-zero `results` count (this is the visibility win; it appears under **Security → Code scanning**).

---

### Task 3 (CONTINGENT): Triage the first scan result

Do this **only if Task 2's scan step exited `FAIL`** with one or more fixable CRITICALs. If it printed `PASS`, skip this task entirely — the feature is done.

**Files:**
- Modify: `Dockerfile` (option A — pin an updated package), **or**
- Create/modify: `.trivyignore` at repo root (option B — justified suppression)

- [ ] **Step 1: Read the flagged vulnerabilities**

From the CI log's `[scan-image] FAIL:` block (or run `./scripts/scan-image.sh hermes-desktop:latest` locally), note each line's `CVE-id`, `PkgName`, `installed=`, `fixed=`.

- [ ] **Step 2A: If the package is one this image installs — bump it in the `Dockerfile`**

Find the `apt-get install`/download line for `PkgName` and pin the fixed version, e.g.:
```dockerfile
# before: apt-get install -y --no-install-recommends <pkg>
# after:  pin to the fixed version Trivy reported (fixed=<version>)
RUN apt-get update && apt-get install -y --no-install-recommends "<pkg>=<fixed-version>" && rm -rf /var/lib/apt/lists/*
```
(For a package baked into the base image with no newer apt candidate, use Step 2B instead.)

- [ ] **Step 2B: If there is no practical fix yet — add a justified `.trivyignore`**

Create/append `.trivyignore` at the repo root. Trivy reads it automatically and drops these from **both** the SARIF report and the gate:
```
# .trivyignore — suppress specific vulnerabilities from the Trivy gate.
# One CVE id per line, each with a reason + date. Revisit dated entries.
# <CVE-ID>  # <why it can't be fixed now / accepted-risk rationale> (added 2026-07-01)
```
Replace `<CVE-ID>` and the comment with the real values from Step 1. Every entry MUST carry a reason.

- [ ] **Step 3: Re-scan and confirm green**

If you took Step 2A, rebuild first: `docker compose build`. Then:
```bash
./scripts/scan-image.sh hermes-desktop:latest; echo "exit=$?"
```
Expected: `[scan-image] PASS` (exit 0).

- [ ] **Step 4: Commit**

```bash
git add Dockerfile .trivyignore 2>/dev/null; git commit -m "fix(security): remediate fixable CRITICAL vuln(s) surfaced by Trivy gate"
```
(Adjust the `git add` to whichever file you changed.)

---

## Notes / assumptions to confirm on first dispatch

- **CodeQL default setup is `not-configured`** (verified 2026-07-01), so `github/codeql-action/upload-sarif` uploads without the "default setup enabled" conflict, and the first upload initializes the repo's code-scanning results.
- **Trivy vuln DB** is pulled from `ghcr.io` at scan time (public, no auth). If a run hits a ghcr pull rate limit, add DB caching via `setup-trivy` (`cache: true`) or set `TRIVY_DB_REPOSITORY`; not expected at this repo's volume.
- **`if: always()` on the scan steps** means a run whose *verify gate* failed (but whose build succeeded) still scans and reports — the image exists. A run whose *build* failed skips the scan cleanly (`steps.img.outputs.built == 'false'`).
- **The gate can legitimately go red on the first run** if the current image ships a fixable CRITICAL — that is Task 3, not a bug. Unfixable OS CVEs never fail the gate (they lack a `FixedVersion`).
- **SARIF still uploads when the gate fails**: the scan step writes `trivy.sarif` before the gate check, and the upload step is `if: always()`, so the job goes red on the gate while code scanning still receives the findings.

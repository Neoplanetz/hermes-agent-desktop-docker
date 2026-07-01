# CI: Trivy image vulnerability scan (amd64 gate + code-scanning report)

- **Date:** 2026-07-01
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

The image is published publicly and its CI (`ci-verify.yml`) already builds it from
source and runs the full `verify-*.sh` gate suite on every PR/push. Repo-level supply-chain
hygiene is on — Dependabot, secret-scanning, push-protection — but there is one uncovered
layer:

- **The built image itself is never scanned for CVEs.** Dependabot only sees *declared*
  dependencies (GitHub Actions, and would see language manifests if any). Nobody looks at
  the vulnerabilities in the ~6 GB runtime artifact — the Ubuntu base, bundled Chrome,
  `xrdp`, `tigervnc`, and the rest of the desktop stack. For a public *security-focused*
  automation image, that is the most conspicuous gap.

**Decision:** add a [Trivy](https://github.com/aquasecurity/trivy) image scan to the
existing amd64 CI. It reuses the image the verify job already builds (no second build),
uploads **all findings** to the GitHub code-scanning dashboard for visibility, and **fails
CI only on fixable CRITICAL** vulnerabilities — a narrow, actionable gate that keeps the
currently-green CI green while surfacing the one class of finding worth blocking on.

## 2. Goals (in scope)

- **Scan the built image on every PR/push.** Reuse `hermes-desktop:latest` (built by
  `scripts/verify-all.sh` in the existing `verify` job) — one build, one scan.
- **Visibility (non-blocking).** Upload the full-severity result as SARIF to GitHub code
  scanning (Security tab). Free for public repos.
- **Narrow gate (blocking).** Fail the job only when Trivy finds a **CRITICAL** vulnerability
  that has a **fix available** (`--severity CRITICAL --ignore-unfixed`).
- **Vulnerability scanning only** (`--scanners vuln`) — OS packages + any language deps. No
  secret/config/license scanning.
- **Zero secrets.** Scan and gate use no secrets; the SARIF upload uses the built-in
  `GITHUB_TOKEN`.

## 3. Non-goals (YAGNI)

- **SBOM generation** (syft/CycloneDX). Deferred; not needed for the scan-and-gate goal.
- **Image signing** (cosign). Deferred, and it only becomes meaningful once publishing is
  automated (registry push with a digest) — publishing is still the manual
  `docker buildx imagetools` flow.
- **Scheduled scan of the published image.** A weekly pull-and-scan (mirroring
  `arm64-published-verify.yml`) would catch CVEs disclosed *after* release. Valuable and
  cheap, but a separate workflow — documented as the natural next increment, not built now.
- **Separate scan workflow / second build.** Rejected in favor of reusing the existing
  build (the repo's CI ethos treats the ~6 GB build as the dominant cost; doubling it was
  declined).
- **Branch-protection / required checks.** Whether the scan gate blocks merge is a repo
  setting, outside the workflow. Optional follow-up.

## 4. Architecture

One change: extra steps appended to the existing `verify` job in
`.github/workflows/ci-verify.yml`. No new workflow file, no new script.

### 4.1 Why reuse works

`scripts/verify-all.sh` builds `hermes-desktop:latest` via `docker compose up -d --build`,
then tears down with `docker compose down -v`. `down -v` removes the **container and named
volume but not the image** — so after the verify step returns (pass *or* fail), the image is
still present and scannable, as long as the build itself succeeded.

### 4.2 Single scan, two derived outputs

Scan the 6 GB image **once** to JSON, then reprocess that cached JSON twice with
`trivy convert` (no re-scan):

```
verify-all.sh  →  trivy image --scanners vuln --format json -o trivy.json   # scan once, all severities
                  ├─ trivy convert --format sarif -o trivy.sarif trivy.json # → upload (all severities, non-blocking)
                  └─ trivy convert --severity CRITICAL --ignore-unfixed \
                                   --exit-code 1 trivy.json                  # → gate (fixable CRITICAL only)
```

> **Fallback:** if the pinned Trivy version's `convert` does not honor
> `--severity`/`--ignore-unfixed`/`--exit-code`, the gate falls back to a second
> `trivy image --severity CRITICAL --ignore-unfixed --exit-code 1` — cheap, because the
> vuln DB and image layers are already cached from the first scan. The local smoke (§7)
> confirms which path the pinned version supports before CI wiring.

Step sequence added to the `verify` job (all scan steps `if: always()` so they run even when
a verify gate failed, provided the image built; the existing always() teardown stays last):

1. **Install Trivy** — `aquasecurity/setup-trivy` (pinned; see §6).
2. **Scan → JSON** — guard `docker image inspect hermes-desktop:latest` first; if absent
   (build failed) echo and `exit 0` (the PR is already red on the build). Otherwise
   `trivy image --scanners vuln --format json -o trivy.json hermes-desktop:latest`.
3. **Convert → SARIF** — `trivy convert --format sarif -o trivy.sarif trivy.json`
   (skips cleanly if `trivy.json` is absent).
4. **Upload SARIF** — `github/codeql-action/upload-sarif`, **`continue-on-error: true`**
   (see §4.3).
5. **Gate** — `trivy convert --severity CRITICAL --ignore-unfixed --exit-code 1 trivy.json`;
   a fixable CRITICAL exits non-zero and fails the job.

### 4.3 Permissions & fork/Dependabot PR handling ⚠️

The workflow's `permissions:` grows from `contents: read` to also include
**`security-events: write`** (required to upload SARIF to code scanning).

**Fork and Dependabot PRs run with a read-only `GITHUB_TOKEN`**, so the SARIF upload will
fail for them. The upload step is therefore **`continue-on-error: true`**: those PRs still
get the **gate** (which needs no special permission) and the scan in the logs, they just
don't publish to the Security tab. **`push` → `main` is the source of truth** for the
code-scanning dashboard — it runs with full permissions and reliably updates alerts.

### 4.4 Error / edge behavior

- **Build failed → no image.** The `docker image inspect` guard makes the scan a clean no-op
  (`exit 0`); the job is already failing on the build, and downstream convert/upload/gate
  steps skip on the missing `trivy.json`.
- **Trivy DB download hiccup.** Absorbed by Trivy's built-in retry; a hard failure surfaces
  as a red scan step (we want to know if we couldn't scan).
- **Verify gate failed but image built.** Scan still runs (`if: always()`) so the Security
  tab and gate reflect the built image regardless of runtime-gate outcome.

## 5. Gating policy & triage

- **Reported (non-blocking):** every severity, via SARIF → code scanning.
- **Blocking:** CRITICAL **with a fix available** only. Unfixable OS CVEs — abundant in a
  bundled desktop+Chrome image — never turn CI red, avoiding a perma-red gate.
- **First-run expectation:** the gate may go red on day one if the current image genuinely
  ships a fixable CRITICAL. That is a real finding, not a design flaw. Landing this includes
  triaging it: bump the offending package in the `Dockerfile`, or, when there is no
  actionable fix yet, add a **justified `.trivyignore` entry** (CVE id + one-line reason +
  date). Trivy honors `.trivyignore` automatically.

## 6. Conventions / guardrails

- **Action pinning (matches repo convention):** first-party (`actions/*`, `github/*`) by
  version tag (e.g. `github/codeql-action/upload-sarif@v3`, as `actions/checkout@v7` today);
  third-party (`aquasecurity/setup-trivy`) pinned to a **commit SHA with a `# vX` comment**,
  as `peter-evans/dockerhub-description` is. Both are Dependabot-tracked.
- **Trivy version** is pinned (via `setup-trivy`); the vulnerability **DB always refreshes**
  at run time (we want current CVE data).
- The added steps keep the existing header-comment style of the workflow file, documenting
  the new `security-events: write` permission and that no secrets are used.
- `.trivyignore` (if/when created) lives at repo root; every entry carries a reason.

## 7. Verification (how we know it works)

- **Local smoke:** build the image, run the three `trivy` commands — confirm `trivy.sarif`
  is produced and the gate command's exit code behaves (0 when no fixable CRITICAL, 1 when
  one is present).
- **In CI:** the PR that adds these steps is the first real run — confirm the scan runs,
  the gate reports, and (on merge to `main`) results appear under **Security → Code
  scanning**. A deliberate downgrade of a package to a known-fixable-CRITICAL version should
  flip the gate red; reverting returns it green.
- **Fork/Dependabot path:** a Dependabot PR run shows the gate executing and the SARIF
  upload skipped-without-failing (`continue-on-error`).

## 8. Defaults (adjustable in the plan)

- **Gate severity:** CRITICAL + fixable only. (HIGH could be added later once the CRITICAL
  baseline is clean.)
- **Scanners:** `vuln` only.
- **Ignore file:** `.trivyignore` at repo root, created only if a finding needs a
  documented, justified suppression.

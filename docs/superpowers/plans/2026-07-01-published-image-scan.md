# Scheduled published-image Trivy scan — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a weekly (+ dispatch) GitHub Actions workflow that Trivy-scans the published Docker Hub image and opens a de-duplicated issue when it finds a fixable CRITICAL.

**Architecture:** One new workflow file reuses `scripts/scan-image.sh` (already on `main`) against the remote published image — `trivy image` pulls the ref itself — so the same fixable-CRITICAL gate the PR scan uses now watches the released artifact. On the gate failing, a shell step opens one labelled GitHub issue (skipping if an open one already exists). No script changes.

**Tech Stack:** GitHub Actions, Trivy (via `aquasecurity/setup-trivy`), `gh` CLI, Bash.

## Global Constraints

- **Reuse `scripts/scan-image.sh` verbatim** — it scans an image ref (`trivy image --scanners vuln … "$IMG"`; a remote registry ref is pulled by Trivy), writes SARIF, and **exits non-zero on a CRITICAL with a fix available**, printing the offending `CVE / pkg / installed / fixed` lines under a `[scan-image] FAIL:` marker. No new script. Copied from spec §4.1.
- **Triggers:** `schedule` weekly `0 6 * * 4` (Thu 06:00 UTC — spread from the Monday arm64 job) + `workflow_dispatch` with an optional `tag` input (blank → `TAG` env). Runner `ubuntu-latest`. Copied from spec §4/§8.
- **Env single-source:** `IMAGE: neoplanetz/hermes-desktop-docker`, `TAG: 'latest'`. Copied from spec §4.
- **Permissions:** `contents: read` + `issues: write`. Zero secrets (public pull; built-in `GITHUB_TOKEN` files the issue). Copied from spec §2/§4.
- **Alert = issue only**, label `published-image-scan`, **de-duplicated** (skip if an open issue with that label already exists). Copied from spec §2/§3.
- **Distinguish gate-failure from scan/infra error** by grepping the captured log for `[scan-image] FAIL:` — CVE list vs "did not complete" note. Copied from spec §5.
- **Action pinning:** first-party by tag (`actions/checkout@v7`); third-party by SHA + `# vX` (`aquasecurity/setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1`, `version: v0.72.0`). Copied from spec §6.
- **No SARIF upload, no arm64-variant scan, no auto-republish, no HIGH gating.** Copied from spec §3.
- **⚠️ Pushing `.github/workflows/*` needs the gh token `workflow` scope** (`gh auth refresh -h github.com -s workflow`) — only affects the acceptance push.

---

### Task 1: Create `.github/workflows/published-image-scan.yml`

**Files:**
- Create: `.github/workflows/published-image-scan.yml`

**Interfaces:**
- Consumes: `scripts/scan-image.sh` (on `main`), invoked as `./scripts/scan-image.sh "<IMAGE>:<tag>"`.
- Produces: a workflow `Scan published image (Trivy)` — weekly + dispatch — that scans the published image and opens a `published-image-scan`-labelled issue on a fixable CRITICAL.

- [ ] **Step 1: Write `.github/workflows/published-image-scan.yml`**

```yaml
# Scheduled Trivy scan of the PUBLISHED image.
#
# Pulls the published Docker Hub image and scans it with scripts/scan-image.sh
# (Trivy pulls the remote ref itself). The reused gate fails on a CRITICAL that has
# a fix available; on failure this opens a de-duplicated GitHub issue — an actionable
# "rebuild & republish" alert for CVEs disclosed after release, in the artifact users
# pull. Source-change CVEs are already caught by ci-verify.yml.
#
# Triggers: weekly schedule (Thu 06:00 UTC), manual (workflow_dispatch w/ tag input)
# Runner:   ubuntu-latest
# Secrets:  none (public image pull; GITHUB_TOKEN files the issue)
name: Scan published image (Trivy)

on:
  schedule:
    - cron: '0 6 * * 4'   # Thursdays 06:00 UTC (spread from the Monday arm64 job)
  workflow_dispatch:
    inputs:
      tag:
        description: 'Published image tag to scan (blank = the TAG env default)'
        required: false

permissions:
  contents: read
  issues: write

env:
  IMAGE: neoplanetz/hermes-desktop-docker
  TAG: 'latest'

jobs:
  scan-published:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Install Trivy
        uses: aquasecurity/setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1
        with:
          version: v0.72.0

      - name: Resolve tag
        id: tag
        env:
          INPUT_TAG: ${{ github.event.inputs.tag }}
        run: echo "tag=${INPUT_TAG:-$TAG}" >> "$GITHUB_OUTPUT"

      - name: Scan the published image
        id: scan
        env:
          IMG_REF: ${{ env.IMAGE }}:${{ steps.tag.outputs.tag }}
        run: |
          set -o pipefail
          ./scripts/scan-image.sh "$IMG_REF" | tee "$RUNNER_TEMP/scan.log"

      - name: Open a de-duplicated issue on a fixable CRITICAL
        if: failure()
        env:
          GH_TOKEN: ${{ github.token }}
          IMG_REF: ${{ env.IMAGE }}:${{ steps.tag.outputs.tag }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          LABEL=published-image-scan
          gh label create "$LABEL" --color B60205 \
            --description "Trivy scan of the published image found a fixable CRITICAL" 2>/dev/null || true
          existing=$(gh issue list --label "$LABEL" --state open --json number --jq 'length')
          if [ "${existing:-0}" -gt 0 ]; then
            echo "an open '$LABEL' issue already exists; not opening a duplicate"
            exit 0
          fi
          if grep -q '\[scan-image\] FAIL:' "$RUNNER_TEMP/scan.log" 2>/dev/null; then
            detail=$(sed -n '/\[scan-image\] FAIL:/,/Remediate:/p' "$RUNNER_TEMP/scan.log")
            title="Published image has a fixable CRITICAL (${IMG_REF})"
            intro="The scheduled Trivy scan of the published image \`${IMG_REF}\` found a CRITICAL vulnerability with a fix available. Rebuild from current source and republish (manual \`buildx\` flow), or add a justified \`.trivyignore\` entry."
          else
            detail=$(tail -n 30 "$RUNNER_TEMP/scan.log" 2>/dev/null || echo '(no scan log captured)')
            title="Published-image scan did not complete (${IMG_REF})"
            intro="The scheduled Trivy scan of \`${IMG_REF}\` failed to run (likely a Trivy DB or registry pull error, not a confirmed CVE). Re-run \`Scan published image (Trivy)\` to confirm."
          fi
          gh issue create --label "$LABEL" \
            --title "$title" \
            --body "$(printf '%s\n\nRun: %s\n\n```\n%s\n```\n' "$intro" "$RUN_URL" "$detail")"
```

- [ ] **Step 2: Validate the YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/published-image-scan.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Smoke-test the issue-body shell logic locally (no GitHub calls)**

The new, error-prone part is the log parsing. Verify it against a synthetic gate-failure log — this exercises the `grep`/`sed`/`printf` without `gh`:

```bash
cat > /tmp/scan.log <<'EOF'
[scan-image] scanning neoplanetz/hermes-desktop-docker:latest (vuln only) -> trivy.json
[scan-image] gate: CRITICAL vulns that have a fix available
[scan-image] FAIL: 1 fixable CRITICAL vuln(s):
  CVE-2025-0001	libexample	installed=1.0.0	fixed=1.0.1
[scan-image] Remediate: bump the package in the Dockerfile, or add a justified
EOF
RUNNER_TEMP=/tmp
if grep -q '\[scan-image\] FAIL:' "$RUNNER_TEMP/scan.log"; then
  detail=$(sed -n '/\[scan-image\] FAIL:/,/Remediate:/p' "$RUNNER_TEMP/scan.log")
  title="Published image has a fixable CRITICAL (neoplanetz/hermes-desktop-docker:latest)"
else
  detail=$(tail -n 30 "$RUNNER_TEMP/scan.log"); title="did-not-complete"
fi
printf 'TITLE: %s\n---BODY DETAIL---\n%s\n' "$title" "$detail"
```
Expected: TITLE names the fixable CRITICAL; the BODY DETAIL block contains the `CVE-2025-0001 … fixed=1.0.1` line and the `Remediate:` line. (Then `rm -f /tmp/scan.log`.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/published-image-scan.yml
git commit -m "ci: scheduled Trivy scan of the published image (issue on fixable CRITICAL)"
```

- [ ] **Step 5: Acceptance — push + dispatch on GitHub**

Pushing the workflow file needs the `workflow` token scope:
```bash
gh auth refresh -s workflow   # only if the push is rejected for missing 'workflow' scope
git push -u origin published-image-scan
gh workflow run "Scan published image (Trivy)" --ref published-image-scan
sleep 5
gh run watch "$(gh run list --workflow='Scan published image (Trivy)' --branch published-image-scan --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: the run installs Trivy, pulls `neoplanetz/hermes-desktop-docker:latest`, scans it, and — since current source (and thus the published image) has **0 fixable CRITICAL** — the scan step prints `[scan-image] PASS` and the run is **green with no issue opened**.

To exercise the issue path (optional, one-off): dispatch with `-f tag=<a-tag-known-to-have-a-fixable-CRITICAL>` if one exists, or temporarily point the `IMAGE` env at a deliberately-vulnerable public image on a throwaway branch; confirm exactly one `published-image-scan`-labelled issue opens with the CVE lines, then re-dispatch and confirm the de-dup skips a second issue. Close the test issue afterward.

---

## Notes / assumptions to confirm on first dispatch

- **`trivy image` on a remote ref** pulls the image itself on `ubuntu-latest` (no Docker `pull`/daemon step needed); it scans the **amd64** manifest of the multi-arch index by default, which is the representative platform (spec §3).
- **`gh label create`** is idempotent here via `|| true`; the first real run creates the `published-image-scan` label.
- **Scheduled runs execute on the default branch** with a full-permission `GITHUB_TOKEN`, so `issues: write` + `gh issue create` work without secrets.
- The current published image is expected to scan **clean** (the source scan at `82e1e77` reported 0 CRITICAL), so the happy-path acceptance opens no issue — that is success, not a silent miss.

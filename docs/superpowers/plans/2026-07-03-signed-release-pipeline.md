# Signed release pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `v*`-tag-driven GitHub Actions workflow that builds `amd64`+`arm64` natively, merges to a multi-arch index, and — before applying the public `:X.Y.Z`/`:latest` tags — runs a Trivy gate, then keyless-signs (cosign/OIDC) and attaches an SPDX SBOM + SLSA v1.0 provenance attestation.

**Architecture:** Two error-prone shell pieces (version/pre-release derivation, SLSA predicate assembly) are extracted into locally-testable `scripts/release-*.sh` helpers (matching the repo's `scan-image.sh`/`verify-*.sh` pattern). A thin `release.yml` wires them: a build matrix pushes each arch **by digest** (untagged) and uploads the digest as an artifact; a `release` job downloads both, merges to an intermediate `:sha-<short>` ref, gates with `scripts/scan-image.sh`, signs+attests the index digest with cosign, then applies the public tags **last**. So a published tag always resolves to a signed, attested digest.

**Tech Stack:** GitHub Actions (matrix + native `ubuntu-24.04-arm`), Docker Buildx (`build-push-action`, `imagetools`), Trivy (`aquasecurity/setup-trivy`), cosign (`sigstore/cosign-installer`, keyless), Bash, `jq`.

## Global Constraints

- **Image (single-source `env`):** `IMAGE: neoplanetz/hermes-desktop-docker`. Copied from spec §4.
- **Trigger:** `push: tags: ['v*']` + `workflow_dispatch` (inputs `version`, `dry_run`). Copied from spec §2/§4.
- **Native multi-arch:** `amd64` on `ubuntu-latest`, `arm64` on `ubuntu-24.04-arm` (no QEMU). Each arch pushes **by digest, untagged**. Copied from spec §2/§4.2.
- **"Published tag ⇒ signed" ordering:** merge → gate → **sign + attest** → **then** apply public tags (`:X.Y.Z`; `:latest` only when NOT pre-release). Copied from spec §2/§4.3.
- **Version rule:** tag `v1.2.0` → `VERSION=1.2.0`; validate `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$`; **pre-release** = contains `-` → push `:VERSION` only, do **not** move `:latest`. Copied from spec §4.1.
- **Keyless everything:** `cosign sign` + `cosign attest --type spdxjson` (Trivy-generated SBOM) + `cosign attest --type slsaprovenance1`, all OIDC keyless; consumers verify with `cosign` alone. Copied from spec §2/§4.
- **Pre-publish gate:** reuse `scripts/scan-image.sh` (fixable CRITICAL → non-zero → release fails before signing/tagging). Copied from spec §2/§4.3.
- **Permissions (top-level, minimal):** `id-token: write` + `contents: read`. No `packages`. Copied from spec §4.
- **Secrets:** existing `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` (Read/Write). **No new secrets.** Copied from spec §4.
- **Concurrency:** `group: release-${{ github.ref }}`, `cancel-in-progress: false`. Copied from spec §4.
- **Action pinning:** first-party by tag (`actions/checkout@v7`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`); third-party by SHA + `# vX` (`setup-buildx-action`, `login-action`, `build-push-action`, `cosign-installer`, and `setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1`, `version: v0.72.0`). Copied from spec §6.
- **Intermediate ref kept:** `:sha-<short>` is retained (not deleted — Docker Hub tag deletion needs the Hub account API, fragile). It is a per-build handle and preserves the sign-then-tag guarantee. (Refines spec §8.)
- **Out of scope:** GitHub Release object, GHCR mirror, keyed signing, CycloneDX, per-arch SBOM/scan, `:latest`-regression guard, back-filling 1.0.0/1.1.0. Copied from spec §3.
- **⚠️ Pushing `.github/workflows/*` needs the gh token `workflow` scope** (`gh auth refresh -s workflow`) — affects the acceptance push only.

---

### Task 1: `scripts/release-meta.sh` — version + pre-release derivation

**Files:**
- Create: `scripts/release-meta.sh`

**Interfaces:**
- Consumes: one CLI arg — a version candidate (`v1.2.0`, `1.2.0`, or `1.2.0-rc1`).
- Produces: prints two lines to stdout — `VERSION=<x.y.z[-pre]>` and `PRERELEASE=<true|false>`; exits non-zero on a non-semver input. Consumed by `release.yml`'s `meta` step (appended to `$GITHUB_OUTPUT`).

- [ ] **Step 1: Write the failing test harness**

Create `/tmp/test-release-meta.sh`:
```bash
#!/usr/bin/env bash
set -u
S=./scripts/release-meta.sh
fail=0
check() { # desc | expected-stdout | actual-stdout | expected-rc | actual-rc
  if [ "$2" != "$3" ] || [ "$4" != "$5" ]; then
    printf 'FAIL: %s\n  want rc=%s out=<%s>\n  got  rc=%s out=<%s>\n' "$1" "$4" "$2" "$5" "$3"; fail=1
  else printf 'ok: %s\n' "$1"; fi
}
out=$("$S" v1.2.0 2>/dev/null); rc=$?
check "tag v1.2.0" "VERSION=1.2.0
PRERELEASE=false" "$out" 0 "$rc"
out=$("$S" 1.2.0 2>/dev/null); rc=$?
check "bare 1.2.0" "VERSION=1.2.0
PRERELEASE=false" "$out" 0 "$rc"
out=$("$S" v1.2.0-rc1 2>/dev/null); rc=$?
check "prerelease v1.2.0-rc1" "VERSION=1.2.0-rc1
PRERELEASE=true" "$out" 0 "$rc"
out=$("$S" 1.2 2>/dev/null); rc=$?
check "reject 1.2 (rc=1)" "" "$out" 1 "$rc"
out=$("$S" "1.2.0; rm -rf /" 2>/dev/null); rc=$?
check "reject injection (rc=1)" "" "$out" 1 "$rc"
exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/test-release-meta.sh`
Expected: FAIL (script missing) — e.g. every `check` reports a non-zero rc mismatch / empty output.

- [ ] **Step 3: Write `scripts/release-meta.sh`**

```bash
#!/usr/bin/env bash
# release-meta.sh — derive & validate release version metadata.
#
# Usage: release-meta.sh <version-candidate>   e.g. "v1.2.0" | "1.2.0" | "1.2.0-rc1"
# Prints (stdout), for appending to $GITHUB_OUTPUT:
#   VERSION=1.2.0
#   PRERELEASE=false     # true when VERSION carries a pre-release suffix (has '-')
# Exits non-zero with a message on a malformed (non-semver / non-Docker-tag) input.
set -euo pipefail

raw="${1:?usage: release-meta.sh <version-candidate>}"
version="${raw#v}"                       # strip a single leading 'v'

# X.Y.Z with an optional -prerelease suffix. The charset also keeps VERSION a
# valid Docker tag, so a hand-typed dispatch input can't forge a ref.
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "release-meta: invalid version '$raw' (expected vX.Y.Z or X.Y.Z[-pre])" >&2
  exit 1
fi

if [[ "$version" == *-* ]]; then prerelease=true; else prerelease=false; fi

echo "VERSION=$version"
echo "PRERELEASE=$prerelease"
```
Then: `chmod +x scripts/release-meta.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash /tmp/test-release-meta.sh; echo "rc=$?"`
Expected: all `ok:` lines, final `rc=0`. (Then `rm -f /tmp/test-release-meta.sh`.)

- [ ] **Step 5: Commit**

```bash
git add scripts/release-meta.sh
git commit -m "feat(release): add release-meta.sh (version + prerelease derivation)"
```

---

### Task 2: `scripts/release-provenance.sh` — SLSA v1.0 predicate emitter

**Files:**
- Create: `scripts/release-provenance.sh`

**Interfaces:**
- Consumes (env, all required): `REPO_URL`, `REF`, `COMMIT`, `BUILDER_ID`, `RUN_URL`.
- Produces: prints a SLSA v1.0 provenance **predicate** JSON to stdout (for `cosign attest --type slsaprovenance1 --predicate -`/file). Consumed by `release.yml`'s provenance step.

- [ ] **Step 1: Write the failing test harness**

Create `/tmp/test-release-prov.sh`:
```bash
#!/usr/bin/env bash
set -u
S=./scripts/release-provenance.sh
export REPO_URL="https://github.com/Neoplanetz/hermes-agent-desktop-docker"
export REF="refs/tags/v1.2.0"
export COMMIT="0123456789abcdef0123456789abcdef01234567"
export BUILDER_ID="$REPO_URL/.github/workflows/release.yml@$REF"
export RUN_URL="$REPO_URL/actions/runs/42/attempts/1"
json=$("$S"); rc=$?
[ "$rc" = 0 ] || { echo "FAIL: nonzero rc=$rc"; exit 1; }
echo "$json" | jq -e . >/dev/null || { echo "FAIL: not valid JSON"; exit 1; }
[ "$(echo "$json" | jq -r '.buildDefinition.resolvedDependencies[0].digest.gitCommit')" = "$COMMIT" ] \
  || { echo "FAIL: gitCommit mismatch"; exit 1; }
[ "$(echo "$json" | jq -r '.runDetails.builder.id')" = "$BUILDER_ID" ] \
  || { echo "FAIL: builder.id mismatch"; exit 1; }
[ "$(echo "$json" | jq -r '.runDetails.metadata.invocationId')" = "$RUN_URL" ] \
  || { echo "FAIL: invocationId mismatch"; exit 1; }
( unset COMMIT; "$S" >/dev/null 2>&1 ) && { echo "FAIL: missing env should exit nonzero"; exit 1; }
echo "ok: provenance predicate valid + fields correct + fails on missing env"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/test-release-prov.sh`
Expected: FAIL (script missing).

- [ ] **Step 3: Write `scripts/release-provenance.sh`**

```bash
#!/usr/bin/env bash
# release-provenance.sh — emit a SLSA v1.0 provenance predicate for the release.
#
# Reads from env (all required):
#   REPO_URL    e.g. https://github.com/Neoplanetz/hermes-agent-desktop-docker
#   REF         e.g. refs/tags/v1.2.0
#   COMMIT      the git commit SHA the tag points at
#   BUILDER_ID  https://github.com/<owner>/<repo>/.github/workflows/release.yml@<ref>
#   RUN_URL     the Actions run URL (used as invocationId)
# Prints the predicate body for `cosign attest --type slsaprovenance1`.
set -euo pipefail
: "${REPO_URL:?}" "${REF:?}" "${COMMIT:?}" "${BUILDER_ID:?}" "${RUN_URL:?}"

jq -n \
  --arg repo "$REPO_URL" --arg ref "$REF" --arg commit "$COMMIT" \
  --arg builder "$BUILDER_ID" --arg run "$RUN_URL" \
  '{
    buildDefinition: {
      buildType: "https://github.com/Neoplanetz/hermes-agent-desktop-docker/release@v1",
      externalParameters: { repository: $repo, ref: $ref },
      internalParameters: {},
      resolvedDependencies: [
        { uri: ("git+" + $repo + "@" + $ref), digest: { gitCommit: $commit } }
      ]
    },
    runDetails: {
      builder: { id: $builder },
      metadata: { invocationId: $run }
    }
  }'
```
Then: `chmod +x scripts/release-provenance.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash /tmp/test-release-prov.sh; echo "rc=$?"`
Expected: `ok: provenance predicate valid ...` then `rc=0`. (Then `rm -f /tmp/test-release-prov.sh`.)

- [ ] **Step 5: Commit**

```bash
git add scripts/release-provenance.sh
git commit -m "feat(release): add release-provenance.sh (SLSA v1.0 predicate emitter)"
```

---

### Task 3: `.github/workflows/release.yml` — the pipeline

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/release-meta.sh`, `scripts/release-provenance.sh`, `scripts/scan-image.sh` (all on the branch); secrets `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`.
- Produces: a `Release (build, push, sign, attest)` workflow — on `v*` tag / dispatch — that publishes a signed, SBOM+provenance-attested multi-arch `:X.Y.Z` (+ `:latest`).

- [ ] **Step 1: Resolve the third-party action SHAs**

Run:
```bash
for a in "docker/setup-buildx-action:v3" "docker/login-action:v3" \
         "docker/build-push-action:v6" "sigstore/cosign-installer:v3"; do
  repo="${a%:*}"; tag="${a#*:}"
  printf '        uses: %s@%s # %s\n' "$repo" "$(gh api "repos/$repo/commits/$tag" --jq .sha)" "$tag"
done
```
Expected: four `uses:` lines with 40-char SHAs. Use these exact lines in place of the four `@v3`/`@v6` `uses:` lines below (repo convention: SHA + `# vX`).

- [ ] **Step 2: Write `.github/workflows/release.yml`**

(Write exactly this, substituting the four resolved `uses:` lines from Step 1 for `docker/*` and `sigstore/cosign-installer`.)

```yaml
# Signed release pipeline. On a 'v*' tag (or manual dispatch), build amd64 + arm64
# on NATIVE runners, merge to a multi-arch index, and — BEFORE applying the public
# :X.Y.Z / :latest tags — run a Trivy gate, then keyless-sign (cosign, GitHub OIDC)
# and attach an SPDX SBOM + SLSA v1.0 provenance attestation. Public tags are applied
# LAST, so a published tag always resolves to a signed, attested digest.
#
# Triggers: push tag 'v*'; workflow_dispatch (version override + dry_run rehearsal)
# Runners:  ubuntu-latest (amd64 build + release/merge), ubuntu-24.04-arm (arm64 build)
# Secrets:  DOCKERHUB_USERNAME + DOCKERHUB_TOKEN (existing, Read/Write). No new secrets.
name: Release (build, push, sign, attest)

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to (re)release, e.g. 1.2.0 or 1.2.0-rc1 (required on dispatch)'
        required: false
      dry_run:
        description: 'Build + gate only; skip signing, attestation, and public tags'
        type: boolean
        default: false

permissions:
  contents: read
  id-token: write        # keyless cosign / OIDC

env:
  IMAGE: neoplanetz/hermes-desktop-docker

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    strategy:
      fail-fast: true
      matrix:
        include:
          - platform: linux/amd64
            runner: ubuntu-latest
            arch: amd64
          - platform: linux/arm64
            runner: ubuntu-24.04-arm
            arch: arm64
    runs-on: ${{ matrix.runner }}
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3 # v3  (replace with SHA from Step 1)
      - name: Log in to Docker Hub
        uses: docker/login-action@v3 # v3  (replace with SHA from Step 1)
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: Build and push by digest
        id: build
        uses: docker/build-push-action@v6 # v6  (replace with SHA from Step 1)
        with:
          context: .
          platforms: ${{ matrix.platform }}
          provenance: false   # we attach SLSA provenance ourselves post-merge (keep per-arch push a plain manifest)
          sbom: false
          outputs: type=image,name=${{ env.IMAGE }},push-by-digest=true,name-canonical=true,push=true
      - name: Export digest to a file
        run: |
          mkdir -p "$RUNNER_TEMP/digests"
          echo "${{ steps.build.outputs.digest }}" > "$RUNNER_TEMP/digests/${{ matrix.arch }}"
      - name: Upload digest artifact
        uses: actions/upload-artifact@v4
        with:
          name: digest-${{ matrix.arch }}
          path: ${{ runner.temp }}/digests/${{ matrix.arch }}
          retention-days: 1
          if-no-files-found: error

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3 # v3  (replace with SHA from Step 1)
      - name: Log in to Docker Hub
        uses: docker/login-action@v3 # v3  (replace with SHA from Step 1)
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: Install Trivy
        uses: aquasecurity/setup-trivy@81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1
        with:
          version: v0.72.0
      - name: Install cosign
        uses: sigstore/cosign-installer@v3 # v3  (replace with SHA from Step 1)
      - name: Download digest artifacts
        uses: actions/download-artifact@v4
        with:
          path: ${{ runner.temp }}/digests
          pattern: digest-*
          merge-multiple: true
      - name: Resolve release metadata
        id: meta
        env:
          RAW_VERSION: ${{ github.event.inputs.version || github.ref_name }}
        run: ./scripts/release-meta.sh "$RAW_VERSION" | tee -a "$GITHUB_OUTPUT"
      - name: Validate + assemble arch digests
        id: digests
        run: |
          amd64="$(cat "$RUNNER_TEMP/digests/amd64")"
          arm64="$(cat "$RUNNER_TEMP/digests/arm64")"
          for d in "$amd64" "$arm64"; do
            [[ "$d" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "bad digest: '$d'" >&2; exit 1; }
          done
          echo "amd64=$amd64" >> "$GITHUB_OUTPUT"
          echo "arm64=$arm64" >> "$GITHUB_OUTPUT"
      - name: Merge to intermediate ref, resolve index digest
        id: merge
        env:
          AMD64: ${{ steps.digests.outputs.amd64 }}
          ARM64: ${{ steps.digests.outputs.arm64 }}
        run: |
          short="${GITHUB_SHA:0:12}"
          tmp="${IMAGE}:sha-${short}"
          docker buildx imagetools create -t "$tmp" "${IMAGE}@${AMD64}" "${IMAGE}@${ARM64}"
          D="$(docker buildx imagetools inspect "$tmp" --format '{{.Manifest.Digest}}')"
          [[ "$D" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "bad index digest: '$D'" >&2; exit 1; }
          echo "tmp=$tmp" >> "$GITHUB_OUTPUT"
          echo "digest=$D" >> "$GITHUB_OUTPUT"
      - name: Trivy gate (a fixable CRITICAL fails the release)
        env:
          IMG_REF: ${{ env.IMAGE }}@${{ steps.merge.outputs.digest }}
        run: ./scripts/scan-image.sh "$IMG_REF"
      - name: Sign the index (keyless)
        if: ${{ github.event.inputs.dry_run != 'true' }}
        env:
          DIGEST_REF: ${{ env.IMAGE }}@${{ steps.merge.outputs.digest }}
        run: cosign sign --yes "$DIGEST_REF"
      - name: Generate + attest SBOM (SPDX)
        if: ${{ github.event.inputs.dry_run != 'true' }}
        env:
          DIGEST_REF: ${{ env.IMAGE }}@${{ steps.merge.outputs.digest }}
        run: |
          trivy image --format spdx-json --output sbom.spdx.json "$DIGEST_REF"
          cosign attest --yes --replace --type spdxjson --predicate sbom.spdx.json "$DIGEST_REF"
      - name: Attest SLSA provenance
        if: ${{ github.event.inputs.dry_run != 'true' }}
        env:
          DIGEST_REF: ${{ env.IMAGE }}@${{ steps.merge.outputs.digest }}
          REPO_URL: ${{ github.server_url }}/${{ github.repository }}
          REF: ${{ github.ref }}
          COMMIT: ${{ github.sha }}
          BUILDER_ID: ${{ github.server_url }}/${{ github.repository }}/.github/workflows/release.yml@${{ github.ref }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}/attempts/${{ github.run_attempt }}
        run: |
          ./scripts/release-provenance.sh > provenance.json
          cosign attest --yes --replace --type slsaprovenance1 --predicate provenance.json "$DIGEST_REF"
      - name: Apply public tags (last — only after signing succeeds)
        if: ${{ github.event.inputs.dry_run != 'true' }}
        env:
          VERSION: ${{ steps.meta.outputs.VERSION }}
          PRERELEASE: ${{ steps.meta.outputs.PRERELEASE }}
          DIGEST_REF: ${{ env.IMAGE }}@${{ steps.merge.outputs.digest }}
        run: |
          args=(-t "${IMAGE}:${VERSION}")
          if [ "$PRERELEASE" = "false" ]; then
            args+=(-t "${IMAGE}:latest")
          fi
          docker buildx imagetools create "${args[@]}" "$DIGEST_REF"
      - name: Summary
        if: ${{ always() }}
        env:
          VERSION: ${{ steps.meta.outputs.VERSION }}
          PRERELEASE: ${{ steps.meta.outputs.PRERELEASE }}
          DIGEST: ${{ steps.merge.outputs.digest }}
          DRY: ${{ github.event.inputs.dry_run }}
        run: |
          {
            echo "### Release $VERSION"
            echo ""
            echo "- dry_run: \`${DRY:-false}\`"
            echo "- prerelease: \`$PRERELEASE\` (moves \`:latest\`: $([ "$PRERELEASE" = false ] && echo yes || echo no))"
            echo "- index digest: \`$DIGEST\`"
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 3: Validate the YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 4: Lint the inline shell (syntax) — no runner needed**

Run:
```bash
bash -n scripts/release-meta.sh scripts/release-provenance.sh && echo "bash syntax OK"
```
Expected: `bash syntax OK`. (If `shellcheck` is installed, also run it on both scripts; warnings are advisory.)

- [ ] **Step 5: Confirm the four third-party `uses:` lines are SHA-pinned**

Run:
```bash
grep -nE 'uses: (docker/|sigstore/)' .github/workflows/release.yml
```
Expected: each line is `…@<40-hex-sha> # vX` (NOT `@v3`/`@v6`). If any still show a version tag, replace it with the Step-1 SHA before committing.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: signed release pipeline (build/push/sign + SBOM + SLSA provenance)"
```

---

### Task 4: Docs — "How to verify", and retire the "manual buildx" pointer

**Files:**
- Modify: `README.md`, `README.ko.md`, `README.ja.md`, `README.zh.md` (add a "Verifying the image" section)
- Modify: `DOCKERHUB_OVERVIEW.md` (add a condensed verify note — the Hub Overview is auto-synced from it)
- Modify: `.github/workflows/published-image-scan.yml` (issue intro: "manual buildx flow" → "push a `vX.Y.Z` tag")
- Modify: `docs/E2E-ACCEPTANCE.md` (add a release-pipeline acceptance entry)

**Interfaces:**
- Consumes: the `cosign verify` identity from Task 3 (`…/release.yml@refs/tags/v…`).
- Produces: consumer-facing verification docs; no code.

- [ ] **Step 1: Add "Verifying the image" to `README.md`**

Insert this section just above the "Links"/footer area of `README.md`:
```markdown
## Verifying the image

Every `vX.Y.Z` release is built in GitHub Actions and **keyless-signed with cosign**
(Sigstore), with an SPDX **SBOM** and **SLSA provenance** attestation attached. Verify
before you run it (needs [cosign](https://docs.sigstore.dev/cosign/installation/)):

```bash
IMAGE=neoplanetz/hermes-desktop-docker:latest
IDENTITY='^https://github\.com/Neoplanetz/hermes-agent-desktop-docker/\.github/workflows/release\.yml@refs/tags/v'
ISSUER=https://token.actions.githubusercontent.com

cosign verify              "$IMAGE" --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
cosign verify-attestation  "$IMAGE" --type spdxjson       --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
cosign verify-attestation  "$IMAGE" --type slsaprovenance1 --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
```
A successful `cosign verify` prints the verified signature; the two `verify-attestation`
calls confirm the SBOM and provenance were signed by this repo's release workflow.
```

- [ ] **Step 2: Add the localized section to the three translated READMEs**

Add the same section (identical `bash` block; translate only the heading + the two prose sentences) to each file:

`README.ko.md`:
```markdown
## 이미지 검증

모든 `vX.Y.Z` 릴리스는 GitHub Actions에서 빌드되어 **cosign 키리스 서명**(Sigstore)되며,
SPDX **SBOM** 와 **SLSA provenance** 증명이 첨부됩니다. 실행 전에 검증하세요
([cosign](https://docs.sigstore.dev/cosign/installation/) 필요):

```bash
IMAGE=neoplanetz/hermes-desktop-docker:latest
IDENTITY='^https://github\.com/Neoplanetz/hermes-agent-desktop-docker/\.github/workflows/release\.yml@refs/tags/v'
ISSUER=https://token.actions.githubusercontent.com

cosign verify              "$IMAGE" --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
cosign verify-attestation  "$IMAGE" --type spdxjson       --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
cosign verify-attestation  "$IMAGE" --type slsaprovenance1 --certificate-identity-regexp "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
```
`cosign verify` 가 성공하면 서명이 검증된 것이고, 두 `verify-attestation` 호출은 SBOM 과
provenance 가 이 저장소의 릴리스 워크플로로 서명되었음을 확인합니다.
```

`README.ja.md` (heading `## イメージの検証`; sentences: "すべての `vX.Y.Z` リリースは GitHub Actions でビルドされ、**cosign によるキーレス署名**（Sigstore）が施され、SPDX **SBOM** と **SLSA プロベナンス** の証明が添付されます。実行前に検証してください（[cosign](https://docs.sigstore.dev/cosign/installation/) が必要）:" / "`cosign verify` が成功すれば署名が検証されており、2 つの `verify-attestation` は SBOM とプロベナンスがこのリポジトリのリリースワークフローで署名されたことを確認します。") — same `bash` block.

`README.zh.md` (heading `## 验证镜像`; sentences: "每个 `vX.Y.Z` 版本都在 GitHub Actions 中构建并使用 **cosign 无密钥签名**（Sigstore），并附带 SPDX **SBOM** 和 **SLSA 来源证明**。运行前请先验证（需要 [cosign](https://docs.sigstore.dev/cosign/installation/)）:" / "`cosign verify` 成功即表示签名已验证；两个 `verify-attestation` 确认 SBOM 与来源证明由本仓库的发布工作流签名。") — same `bash` block.

- [ ] **Step 3: Add a condensed verify note to `DOCKERHUB_OVERVIEW.md`**

The Hub Overview is auto-synced from this file (`dockerhub-description.yml`). Add a short
"Verify" subsection near the quickstart (Hub users never see the GitHub README):
```markdown
### Verify (cosign)

Releases are keyless-signed with an SBOM + SLSA provenance attestation:
```bash
IMAGE=neoplanetz/hermes-desktop-docker:latest
ID='^https://github\.com/Neoplanetz/hermes-agent-desktop-docker/\.github/workflows/release\.yml@refs/tags/v'
IS=https://token.actions.githubusercontent.com
cosign verify "$IMAGE" --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$IS"
```
Full instructions (SBOM + provenance): see "Verifying the image" in the repo README.
```

- [ ] **Step 4: Retire the "manual buildx" republish pointer**

In `.github/workflows/published-image-scan.yml`, change the fixable-CRITICAL issue `intro` string:
- From: `Rebuild from current source and republish (manual \`buildx\` flow), or add a justified \`.trivyignore\` entry.`
- To: `Rebuild + republish by pushing a \`vX.Y.Z\` git tag (the release workflow rebuilds, signs, and attests), or add a justified \`.trivyignore\` entry.`

Then catch any other stray pointers:
```bash
grep -rn "manual \`buildx\`\|manual buildx\|buildx imagetools create" README*.md DOCKERHUB_OVERVIEW.md docs/ .github/ 2>/dev/null
```
For each hit in a **live** doc (not a historical `docs/superpowers/specs|plans/*` file), update it to the "push a `vX.Y.Z` tag" flow. Leave historical spec/plan files unchanged.

- [ ] **Step 5: Add a release acceptance entry to `docs/E2E-ACCEPTANCE.md`**

Append:
```markdown
## Signed release pipeline (release.yml)

- [ ] **dry_run** — `gh workflow run "Release (build, push, sign, attest)" --ref <branch> -f version=1.1.1-rc1 -f dry_run=true` → builds both arches, merges, Trivy gate passes; **no signing, no public tag**.
- [ ] **pre-release** — push `v1.1.1-rc1` → run green; `cosign verify` + `verify-attestation --type spdxjson` + `--type slsaprovenance1` all succeed; `:1.1.1-rc1` exists and **`:latest` is unchanged**.
- [ ] **release** — push `v1.1.1` → `:1.1.1` and `:latest` resolve to the **same signed** digest; all three cosign checks pass.
```

- [ ] **Step 6: Validate + commit**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/published-image-scan.yml')); print('YAML OK')"
git add README.md README.ko.md README.ja.md README.zh.md DOCKERHUB_OVERVIEW.md \
        .github/workflows/published-image-scan.yml docs/E2E-ACCEPTANCE.md
git commit -m "docs(release): add cosign 'Verifying the image' section; retire manual-buildx pointer"
```

---

### Task 5: Live acceptance — dry-run, pre-release rehearsal, first real release

**Files:** none (operational).

**Interfaces:**
- Consumes: `release.yml` on the branch/main; `DOCKERHUB_*` secrets; cosign installed locally for verification.
- Produces: a verified signed pre-release, then the first signed real release.

> ⚠️ This task **publishes to Docker Hub** (a `:1.1.1-rc1` pre-release, then `:1.1.1`). Run it with the maintainer present. Pushing `.github/workflows/*` needs the `workflow` token scope.

- [ ] **Step 1: Push the branch (workflow scope)**

```bash
gh auth refresh -s workflow    # only if the push is rejected for missing 'workflow' scope
git push -u origin <feature-branch>
```

- [ ] **Step 2: dry_run rehearsal from the branch (no publish, no signing)**

```bash
gh workflow run "Release (build, push, sign, attest)" --ref <feature-branch> -f version=1.1.1-rc1 -f dry_run=true
sleep 5
gh run watch "$(gh run list --workflow='Release (build, push, sign, attest)' --branch <feature-branch> --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: `build` (both arches) + `release` green through the **Trivy gate**; the sign/attest/tag steps are **skipped** (dry_run). No `:1.1.1-rc1`/`:latest` change on Docker Hub. (An intermediate `:sha-<short>` ref is created — expected.)

- [ ] **Step 3: Merge the pipeline to `main`**

Open a PR (branch protection runs the required `verify` check) and merge, or direct-push if that is the maintainer's convention. The `v*` push trigger runs the workflow **as it exists at the tagged commit**, so it must be on `main` before tagging.

- [ ] **Step 4: Pre-release rehearsal (full signing) via a real tag**

```bash
git tag -a v1.1.1-rc1 -m "Pre-release rehearsal of the signed release pipeline"
git push origin v1.1.1-rc1
gh run watch "$(gh run list --workflow='Release (build, push, sign, attest)' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Then verify locally:
```bash
IMG=neoplanetz/hermes-desktop-docker:1.1.1-rc1
ID='^https://github\.com/Neoplanetz/hermes-agent-desktop-docker/\.github/workflows/release\.yml@refs/tags/v'
IS=https://token.actions.githubusercontent.com
cosign verify             "$IMG" --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$IS"
cosign verify-attestation "$IMG" --type spdxjson        --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$IS"
cosign verify-attestation "$IMG" --type slsaprovenance1 --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$IS"
```
Expected: all three succeed. Confirm on Docker Hub that **`:latest` still points at the previous release** (pre-release must not move it). **If the identity regex fails**, read the actual cert identity from the `cosign verify` error and correct the owner casing in the regex (here and in the READMEs) — then this is the moment to fix it before a real release.

- [ ] **Step 5: First real release**

```bash
git tag -a v1.1.1 -m "First signed release"
git push origin v1.1.1
gh run watch "$(gh run list --workflow='Release (build, push, sign, attest)' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Then re-run the three `cosign` checks against `:1.1.1` **and** `:latest`; confirm both resolve to the **same signed** digest. Publish a GitHub Release for the tag if desired (out of the pipeline's scope).

---

## Notes / assumptions to confirm on first run

- **`ubuntu-24.04-arm` is available** to this public repo (GitHub-hosted arm64 runners are GA + free for public repos; `arm64-published-verify.yml` already uses native arm64). If the label ever changes, it is the one line to bump in the `build` matrix.
- **`provenance: false` / `sbom: false` on `build-push-action`** keep each per-arch push a plain single-platform manifest, so `imagetools create` assembles a clean 2-manifest index (we attach provenance/SBOM ourselves post-merge).
- **cosign auth to Docker Hub** rides on `docker/login-action` (the docker keychain); no separate `cosign login`. Signing adds `sha256-<digest>.sig`/`.att` referrer tags to the Hub repo — normal for a signed image, expected in the tag list.
- **cosign identity casing:** the cert SAN uses the repo's stored casing (`Neoplanetz`). The regex is validated for real in Task 5 Step 4 (pre-release) — the safe place to correct it before a real release.
- **SBOM/gate cover the `amd64` platform** of the index (Trivy's default), consistent with `published-image-scan.yml` (amd64 and arm64 share the OS package set).
- **Dispatch requires `version`** (a real X.Y.Z[-pre]); a bare dispatch falls back to the branch name and `release-meta.sh` rejects it with a clear message.
- **Re-running a tag** is safe: `imagetools create` re-tagging is idempotent; `cosign attest --replace` avoids duplicate attestations; extra `cosign sign` signatures verify fine.

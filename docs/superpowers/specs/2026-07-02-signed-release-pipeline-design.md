# Signed release pipeline (build, push, sign, attest)

- **Date:** 2026-07-02
- **Status:** Proposed (awaiting review)
- **Repo:** hermes-agent-desktop-docker

## 1. Context & decision

The published multi-arch image (`neoplanetz/hermes-desktop-docker` — `amd64`+`arm64`) is
built and pushed by a **manual `docker buildx` flow** off a maintainer's machine and unified
with `buildx imagetools create`. CI verifies source (`ci-verify.yml`), verifies the published
arm64 image (`arm64-published-verify.yml`), and scans the published image
(`published-image-scan.yml`) — but nothing **builds and publishes** it, and the published
artifact carries **no signature, no SBOM, and no provenance**. For a security-positioned,
zero-privilege image that people pull from a public registry, "you can't cryptographically
verify who built this or from what source" is the largest remaining gap.

**Decision:** add a `release.yml` workflow that, on a `v*` git tag, builds each architecture
on a native runner, merges them into a multi-arch index, and — **before** the public
`:X.Y.Z` / `:latest` tags are applied — signs the index and attaches an SBOM and SLSA
provenance attestation, all keyless via GitHub OIDC (Sigstore). This replaces the manual
release ritual with a reproducible, signed, attested CI release. It reuses the existing
`scripts/scan-image.sh` and the pinned Trivy setup as a pre-publish gate, and the existing
`DOCKERHUB_*` repo secrets — **no new secrets**.

## 2. Goals (in scope)

- **Tag-driven release.** `push` of a tag matching `v*` builds, publishes, signs, and attests.
  `workflow_dispatch` (with a `version` override and a `dry_run` flag) provides a manual
  re-run / rehearsal path.
- **Native multi-arch build.** `amd64` on `ubuntu-latest`, `arm64` on `ubuntu-24.04-arm`
  (native, no QEMU emulation — free for this public repo). Each arch pushes **by digest**
  (untagged); a merge step assembles the multi-arch index.
- **"Published tag ⇒ signed" ordering.** Public tags (`:X.Y.Z`, and `:latest` for non
  pre-releases) are applied **last**, only after signing + attestation succeed against the
  final index digest. A partial or failed run never exposes a half-built or unsigned tag.
- **Keyless signing (Sigstore/cosign).** `cosign sign` the final index digest via GitHub OIDC
  — no private keys to store or rotate; signature + cert recorded in the Rekor transparency log.
- **SBOM attestation.** Generate an SPDX SBOM with the already-pinned Trivy and attach it with
  `cosign attest --type spdxjson`.
- **SLSA provenance attestation.** Attach an explicit SLSA v1.0 provenance predicate (source
  repo + commit + tag ref + builder id + run id) with `cosign attest --type slsaprovenance1`.
- **Pre-publish Trivy gate.** Reuse `scripts/scan-image.sh` against the freshly built index
  digest; a fixable CRITICAL **fails the release** so a known-vulnerable image is never signed
  or tagged.
- **Single-tool consumer verification.** Everything (signature, SBOM, provenance) is verified
  with `cosign` alone; a "How to verify" snippet is added to the README.
- **Reuse, don't duplicate.** Same `scripts/scan-image.sh`, same pinned `setup-trivy`, same
  `DOCKERHUB_*` secrets, same workflow conventions (SHA-pinned actions, minimal `permissions`,
  single-source `env`, header comment) as the existing workflows.

## 3. Non-goals (YAGNI)

- **No GitHub Release object / auto-generated release notes.** The trigger is the git tag; a
  Release object is a separate concern that can be layered later.
- **No GHCR mirror.** Docker Hub only (that is where the image lives).
- **No keyed (non-keyless) signing.** Keyless GitHub OIDC only — no key material to manage.
- **No CycloneDX SBOM.** One format (SPDX) is enough; a second is redundant.
- **No automatic post-release re-trigger of `arm64-published-verify` / `published-image-scan`.**
  Those keep their existing schedules; coupling them to release adds fragility for little gain.
- **No back-filling signatures for the already-published `1.0.0` / `1.1.0`.** Can be done as a
  one-off later; it is not part of the pipeline.
- **No per-arch SBOM/scan.** SBOM + gate cover the `amd64` platform of the index (the runner
  default), matching `published-image-scan.yml`'s reasoning: `amd64` and `arm64` share the OS
  package set, so a second arch scan is not worth it.
- **No semver "don't move `:latest` backward" enforcement in code.** Documented caution only
  (see §5); tag forward.

## 4. Architecture

One new workflow file: `.github/workflows/release.yml`. No new scripts. Three jobs, fan-in.

- **Triggers:** `push: tags: ['v*']` + `workflow_dispatch` with inputs `version` (optional
  override, e.g. re-run a tag) and `dry_run` (boolean).
- **Permissions (top-level, minimal):** `id-token: write` (OIDC for keyless cosign),
  `contents: read`. No `packages` (Docker Hub, not GHCR).
- **Secrets:** existing `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` (Read/Write). No new secrets.
- **Env:** `IMAGE: neoplanetz/hermes-desktop-docker` (single-source, one line to bump).
- **Concurrency:** `group: release-${{ github.ref }}`, `cancel-in-progress: false` — queue,
  never cancel a release mid-flight.

### 4.1 Version derivation

- From a `push` tag: `VERSION` = tag with the leading `v` stripped (`v1.2.0` → `1.2.0`).
- From `workflow_dispatch`: `VERSION` = the `version` input.
- Validate `VERSION` against `^[0-9]+\.[0-9]+\.[0-9]+(-.+)?$`; fail fast on mismatch.
- **Pre-release** = `VERSION` contains `-` (e.g. `1.2.0-rc1`). Pre-releases push `:VERSION`
  only; **`:latest` is not moved**. Non-pre-releases push `:VERSION` **and** `:latest`.

### 4.2 Build jobs — `build-amd64` (ubuntu-latest), `build-arm64` (ubuntu-24.04-arm)

Identical except runner. Each:
1. Checkout.
2. `docker/setup-buildx-action`.
3. `docker/login-action` with `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`.
4. `docker/build-push-action` with `push-by-digest` (untagged):
   `outputs: type=image,name=${IMAGE},push-by-digest=true,name-canonical=true,push=true`.
5. Emit the resulting digest to a **job output** (`digest=${{ steps.build.outputs.digest }}`
   → `$GITHUB_OUTPUT`).

Because each arch is pushed **by digest with no tag**, nothing a consumer pulls
(`:latest` / `:X.Y.Z`) references it yet.

### 4.3 Release job — `release` (needs: [build-amd64, build-arm64], ubuntu-latest)

1. Checkout (for `scripts/scan-image.sh`); `docker/login-action` (same secrets).
2. **Validate** both incoming digests match `^sha256:[0-9a-f]{64}$`; derive `VERSION`,
   `PRERELEASE`, `SHORT_SHA`.
3. **Merge to an intermediate ref** (public tags not yet applied):
   `docker buildx imagetools create -t ${IMAGE}:sha-${SHORT_SHA} ${IMAGE}@${AMD64} ${IMAGE}@${ARM64}`
4. **Resolve the final index digest** `D`
   (`docker buildx imagetools inspect ${IMAGE}:sha-${SHORT_SHA} --format '{{.Manifest.Digest}}'`).
5. **Trivy gate** — install pinned `setup-trivy`; `./scripts/scan-image.sh ${IMAGE}@${D}`.
   A fixable CRITICAL exits non-zero → the release **fails here**, before signing/tagging.
6. **Sign** — `sigstore/cosign-installer`; `cosign sign --yes ${IMAGE}@${D}` (keyless, OIDC;
   cosign reuses the `docker login` credentials to push the signature referrer to Docker Hub).
7. **SBOM** — `trivy image --format spdx-json --output sbom.spdx.json ${IMAGE}@${D}`;
   `cosign attest --yes --replace --type spdxjson --predicate sbom.spdx.json ${IMAGE}@${D}`.
8. **Provenance** — write an explicit SLSA v1.0 predicate (see §4.4) to `provenance.json`;
   `cosign attest --yes --replace --type slsaprovenance1 --predicate provenance.json ${IMAGE}@${D}`.
9. **Apply public tags last** — `docker buildx imagetools create -t ${IMAGE}:${VERSION}`
   (plus `-t ${IMAGE}:latest` when not a pre-release) `${IMAGE}@${D}`. The public tags now
   point at the already-signed digest `D`; because cosign verifies by digest, the signature
   and attestations are valid for every tag that resolves to `D`.
10. **`dry_run`** short-circuits after step 5: it builds + merges to the intermediate
    `sha-${SHORT_SHA}` ref and runs the gate, but **skips signing, attesting, and public
    tagging** — a safe end-to-end rehearsal.

### 4.4 SLSA provenance predicate (explicit fields)

`provenance.json` is a SLSA v1.0 (`https://slsa.dev/provenance/v1`) predicate assembled in a
shell step from GitHub context, so the content is defined here rather than left implicit:

- `buildDefinition.buildType`: a stable URI for this workflow's build type.
- `buildDefinition.externalParameters`: `{ repository, ref }` (the tag ref).
- `buildDefinition.resolvedDependencies[0]`: `{ uri: "git+<repo>@<ref>", digest: { gitCommit: <sha> } }`.
- `runDetails.builder.id`: `https://github.com/Neoplanetz/hermes-agent-desktop-docker/.github/workflows/release.yml@<ref>`
  (`<ref>` = the tag ref at build time, e.g. `refs/tags/v1.2.0`).
- `runDetails.metadata.invocationId`: the Actions run URL (`…/actions/runs/<run_id>/attempts/<attempt>`).

### 4.5 Consumer verification (README "How to verify")

```
cosign verify neoplanetz/hermes-desktop-docker:1.2.0 \
  --certificate-identity-regexp '^https://github\.com/Neoplanetz/hermes-agent-desktop-docker/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify-attestation --type spdxjson         <same identity flags> neoplanetz/hermes-desktop-docker:1.2.0
cosign verify-attestation --type slsaprovenance1   <same identity flags> neoplanetz/hermes-desktop-docker:1.2.0
```

## 5. Error / edge behavior

- **One build job fails** → the `release` job (`needs: [both]`) never runs → no public tag is
  applied → nothing new is published (safe; this is the point of push-by-digest-then-tag).
- **Gate fails (fixable CRITICAL)** → release stops at §4.3 step 5; no signature, no public
  tag. The image is not shipped. (Remediate source or add a justified `.trivyignore`.)
- **Sign / attest fails** → stops before §4.3 step 9; public tags are never applied, so a
  consumer never sees an unsigned `:X.Y.Z` / `:latest`.
- **Re-run of the same tag** (re-push or dispatch) → `imagetools create` re-tagging is
  idempotent; `cosign attest --replace` avoids duplicate attestations; `cosign sign` is
  additive (extra signatures verify fine). Safe to re-run.
- **Malformed / non-semver tag** → §4.1 validation fails the run immediately.
- **Docker Hub OCI referrers** → cosign uses the OCI 1.1 referrers API with tag-schema
  fallback; Docker Hub supports this, so signatures/attestations attach without a side channel.
- **`:latest` regression** → re-running an *older* tag would move `:latest` backward. Not
  guarded in code (semver comparison is out of scope, §3); documented caution — tag forward.

## 6. Conventions / guardrails

- **All third-party actions pinned by commit SHA + `# vX`** (checkout, setup-buildx, login,
  build-push, cosign-installer, setup-trivy) — matching every existing workflow. `setup-trivy`
  reuses the repo's existing pin (`…81e514348e19b6112ce2a7e3ecbafe19c1e1f567 # v0.3.1`,
  `version: v0.72.0`).
- **Minimal top-level `permissions`** (`id-token: write`, `contents: read`).
- **Single-source `env`** for the image repo (`IMAGE`).
- **Header comment** documents triggers, runners, the "sign-then-tag" ordering, the reuse of
  `scripts/scan-image.sh`, and that it uses the existing `DOCKERHUB_*` secrets (no new secrets).
- **`cosign --yes`** everywhere (non-interactive); modern cosign v2 needs no `COSIGN_EXPERIMENTAL`.

## 7. Verification (how we know it works)

- **`dry_run` dispatch** → builds both arches, merges to `sha-<shortsha>`, runs the Trivy gate,
  and stops — confirm no signing, no attestation, and **no public tag** were produced.
- **Pre-release rehearsal** → push `v1.1.1-rc1` → full run → confirm:
  - `:1.1.1-rc1` exists and `:latest` was **not** moved,
  - `cosign verify` succeeds against the identity regex,
  - `cosign verify-attestation --type spdxjson` and `--type slsaprovenance1` both succeed.
- **First real release** → push `v1.1.1` → confirm `:1.1.1` **and** `:latest` point at the same
  signed digest and all three `cosign` checks pass.
- **Gate path** → a `dry_run` (or pre-release) against a source known to carry a fixable
  CRITICAL fails at the gate step, before any signing/tagging.
- Add the acceptance steps to `docs/E2E-ACCEPTANCE.md`.

## 8. Defaults (adjustable in the plan)

- **Workflow file:** `.github/workflows/release.yml`.
- **arm64 runner label:** `ubuntu-24.04-arm` (the label `arm64-published-verify.yml` uses).
- **Intermediate build ref:** `:sha-<shortsha>` (kept; a stable per-build handle. The plan may
  instead delete it after tagging — decide there).
- **SBOM format:** SPDX JSON (`spdx-json`), attested as `spdxjson`.
- **Provenance:** explicit SLSA v1.0 predicate via `cosign attest --type slsaprovenance1`.
  If the hand-assembled predicate proves brittle in implementation, swapping *only provenance*
  to the first-party `actions/attest-build-provenance` (verified with `gh attestation verify`)
  is a sanctioned plan-time adjustment; update the §4.5 verification snippet accordingly.
- **Doc touch-points:** README "How to verify" (+ `.ko/.ja/.zh`), `DOCKERHUB_OVERVIEW.md`, and
  the "manual `buildx` flow" pointers in `published-image-scan.yml` / any docs → "push a
  `vX.Y.Z` tag."

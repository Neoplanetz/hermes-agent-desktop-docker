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

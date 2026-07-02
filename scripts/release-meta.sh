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

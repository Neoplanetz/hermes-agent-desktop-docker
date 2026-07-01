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

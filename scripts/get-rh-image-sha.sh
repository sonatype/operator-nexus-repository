#!/bin/sh
# Polls the Red Hat connect API until the given image tag is published with scan_status=passed.
# Usage: get-rh-image-sha.sh <projectId> <imageTag> <registryPrefix>
# Output: <registryPrefix>@<digest>  (e.g. registry.connect.redhat.com/sonatype/img@sha256:...)
# Env:
#   RH_API_TOKEN  - Red Hat connect Bearer token (required)
#   RH_API_BASE   - API base URL (default: https://connect.redhat.com)
#   MAX_ATTEMPTS  - number of 60-second retries before timeout (default: 90)

set -e

if [ -z "$RH_API_TOKEN" ]; then
  printf 'ERROR: RH_API_TOKEN must be set\n' >&2
  exit 1
fi

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <projectId> <imageTag> <registryPrefix>\n' "$0" >&2
  exit 1
fi

PROJECT_ID="$1"
IMAGE_TAG="$2"
REGISTRY_PREFIX="$3"
API_BASE="${RH_API_BASE:-https://connect.redhat.com}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-90}"

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  response=$(curl -sf -X POST \
    -H "Authorization: Bearer ${RH_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${API_BASE}/api/v2/projects/${PROJECT_ID}/tags" 2>/dev/null || printf '{}')

  digest=$(printf '%s' "$response" | jq -r --arg tag "$IMAGE_TAG" \
    '[.tags[] | select(.name == $tag and .scan_status == "passed")] | first | .digest // empty' \
    2>/dev/null || true)

  if [ -n "$digest" ]; then
    printf '%s@%s\n' "$REGISTRY_PREFIX" "$digest"
    exit 0
  fi

  attempt=$((attempt + 1))
  remaining=$((MAX_ATTEMPTS - attempt))
  printf 'Tag %s not yet published (attempt %d/%d, %d remaining). Retrying in 60s...\n' \
    "$IMAGE_TAG" "$attempt" "$MAX_ATTEMPTS" "$remaining" >&2
  [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 60
done

printf 'ERROR: Timed out after %d attempts waiting for tag %s (scan_status=passed)\n' \
  "$MAX_ATTEMPTS" "$IMAGE_TAG" >&2
exit 1

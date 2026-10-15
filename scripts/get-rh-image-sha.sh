#!/bin/sh
# Polls the Red Hat catalog (Pyxis) until the given image tag is published and certified, then
# prints its digest. The catalog lists published images to anonymous callers, so no token is needed.
# Usage: get-rh-image-sha.sh <imageTag> <registryPrefix>
# Output: <registryPrefix>@<digest>  (e.g. registry.connect.redhat.com/sonatype/img@sha256:...)
# Env:
#   CATALOG_API_BASE - catalog API base URL (default: https://catalog.redhat.com/api/containers/v1)
#   MAX_ATTEMPTS     - number of 60-second retries before timeout (default: 90)

set -e

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s <imageTag> <registryPrefix>\n' "$0" >&2
  exit 1
fi

IMAGE_TAG="$1"
REGISTRY_PREFIX="$2"
API_BASE="${CATALOG_API_BASE:-https://catalog.redhat.com/api/containers/v1}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-90}"

# registry.connect.redhat.com/sonatype/img -> host=registry.connect.redhat.com repo=sonatype/img
REGISTRY_HOST="${REGISTRY_PREFIX%%/*}"
REPOSITORY="${REGISTRY_PREFIX#*/}"
URL="${API_BASE}/repositories/registry/${REGISTRY_HOST}/repository/${REPOSITORY}/images"
URL="${URL}?filter=repositories.tags.name==${IMAGE_TAG}&include=data.docker_image_digest,data.certified"

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  # -w appends the HTTP status after the body so an error response is not mistaken for
  # "tag not published yet". An unpublished tag is HTTP 200 with an empty data list.
  raw=$(curl -s -w '\n%{http_code}' "$URL" 2>/dev/null || printf '{}\n000')
  http_code=$(printf '%s\n' "$raw" | tail -n 1)
  response=$(printf '%s\n' "$raw" | sed '$d')

  if [ "$http_code" != "200" ]; then
    printf 'ERROR: Red Hat catalog returned HTTP %s for %s tag %s\n' \
      "$http_code" "$REPOSITORY" "$IMAGE_TAG" >&2
    exit 1
  fi

  digests=$(printf '%s' "$response" | jq -r \
    '[.data[]? | select(.certified == true) | .docker_image_digest] | unique | .[]' \
    2>/dev/null || true)
  count=$(printf '%s' "$digests" | grep -c . || true)

  if [ "$count" -gt 1 ]; then
    printf 'ERROR: %d different certified digests found for %s tag %s, refusing to guess:\n%s\n' \
      "$count" "$REPOSITORY" "$IMAGE_TAG" "$digests" >&2
    exit 1
  fi

  if [ "$count" -eq 1 ]; then
    printf '%s@%s\n' "$REGISTRY_PREFIX" "$digests"
    exit 0
  fi

  attempt=$((attempt + 1))
  remaining=$((MAX_ATTEMPTS - attempt))
  printf 'Tag %s not yet published and certified (attempt %d/%d, %d remaining). Retrying in 60s...\n' \
    "$IMAGE_TAG" "$attempt" "$MAX_ATTEMPTS" "$remaining" >&2
  [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 60
done

printf 'ERROR: Timed out after %d attempts waiting for tag %s to be published and certified\n' \
  "$MAX_ATTEMPTS" "$IMAGE_TAG" >&2
exit 1

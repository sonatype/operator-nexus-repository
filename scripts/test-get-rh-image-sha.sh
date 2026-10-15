#!/bin/sh
# No set -e — tests intentionally invoke commands that exit non-zero

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_test() {
  name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Creates a temporary directory containing a mock `curl` binary that prints $1, then the HTTP
# status $2 (default 200) on its own line, mimicking `curl -s -w '\n%{http_code}'`, and exits 0.
# It also records the requested URL in $mock_dir/url.
mock_curl() {
  response="$1"
  code="${2:-200}"
  mock_dir=$(mktemp -d "${TMPDIR:-/tmp}/mock-XXXXXX")
  printf '#!/bin/sh\nfor a in "$@"; do last="$a"; done\nprintf "%%s" "$last" > "%s/url"\nprintf '"'"'%%s\\n%%s\\n'"'"' '"'"'%s'"'"' '"'"'%s'"'"'\n' "$mock_dir" "$response" "$code" > "$mock_dir/curl"
  chmod +x "$mock_dir/curl"
  printf '%s' "$mock_dir"
}

run() {
  PATH="$mock_dir:$PATH" MAX_ATTEMPTS="${1:-1}" "$SCRIPT_DIR/get-rh-image-sha.sh" \
    "3.90.3-1" "registry.connect.redhat.com/sonatype/nxrm"
}

# --- Test 1: returns full image ref when the tag is certified ---
mock_dir=$(mock_curl '{"data":[{"docker_image_digest":"sha256:abc123","certified":true}]}')
actual=$(run 2>/dev/null)
run_test "returns full ref on success" \
  "registry.connect.redhat.com/sonatype/nxrm@sha256:abc123" "$actual"
rm -rf "$mock_dir"

# --- Test 2: builds the catalog URL from the registry prefix and tag ---
mock_dir=$(mock_curl '{"data":[{"docker_image_digest":"sha256:abc123","certified":true}]}')
run >/dev/null 2>&1
run_test "queries the catalog repository and tag" \
  "https://catalog.redhat.com/api/containers/v1/repositories/registry/registry.connect.redhat.com/repository/sonatype/nxrm/images?filter=repositories.tags.name==3.90.3-1&include=data.docker_image_digest,data.certified" \
  "$(cat "$mock_dir/url")"
rm -rf "$mock_dir"

# --- Test 3: unpublished tag (HTTP 200, empty data) keeps polling then times out ---
mock_dir=$(mock_curl '{"data":[]}')
run 1 >/dev/null 2>&1; actual_exit=$?
run_test "exits 1 when tag is not published (timeout)" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 4: uncertified image is ignored ---
mock_dir=$(mock_curl '{"data":[{"docker_image_digest":"sha256:abc123","certified":false}]}')
run 1 >/dev/null 2>&1; actual_exit=$?
run_test "exits 1 when image is not certified" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 5: duplicate records with the same digest are fine ---
mock_dir=$(mock_curl '{"data":[{"docker_image_digest":"sha256:abc123","certified":true},{"docker_image_digest":"sha256:abc123","certified":true}]}')
actual=$(run 2>/dev/null)
run_test "accepts repeated identical digest" \
  "registry.connect.redhat.com/sonatype/nxrm@sha256:abc123" "$actual"
rm -rf "$mock_dir"

# --- Test 6: refuses to guess between different certified digests ---
mock_dir=$(mock_curl '{"data":[{"docker_image_digest":"sha256:aaa","certified":true},{"docker_image_digest":"sha256:bbb","certified":true}]}')
actual_err=$(run 3 2>&1 >/dev/null); actual_exit=$?
run_test "exits 1 on multiple different digests" "1" "$actual_exit"
case "$actual_err" in
  *"refusing to guess"*) run_test "reports ambiguity" "yes" "yes" ;;
  *) run_test "reports ambiguity" "yes" "no: $actual_err" ;;
esac
rm -rf "$mock_dir"

# --- Test 7: exits 1 immediately on a non-200 response, not after retrying ---
mock_dir=$(mock_curl '<html>Not Found</html>' 404)
actual_err=$(run 3 2>&1 >/dev/null); actual_exit=$?
run_test "exits 1 on HTTP 404" "1" "$actual_exit"
case "$actual_err" in
  *"HTTP 404"*) run_test "reports HTTP 404 in error" "yes" "yes" ;;
  *) run_test "reports HTTP 404 in error" "yes" "no: $actual_err" ;;
esac
rm -rf "$mock_dir"

# --- Test 8: exits 1 on HTTP 500 ---
mock_dir=$(mock_curl '{}' 500)
run 3 >/dev/null 2>&1; actual_exit=$?
run_test "exits 1 on HTTP 500" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 9: usage error with wrong argument count ---
"$SCRIPT_DIR/get-rh-image-sha.sh" "only-one" >/dev/null 2>&1; actual_exit=$?
run_test "exits 1 on wrong argument count" "1" "$actual_exit"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

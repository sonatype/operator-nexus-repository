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

# Creates a temporary directory containing a mock `curl` binary that prints $1 and exits 0
mock_curl() {
  response="$1"
  mock_dir=$(mktemp -d)
  printf '#!/bin/sh\nprintf '"'"'%%s'"'"' '"'"'%s'"'"'\n' "$response" > "$mock_dir/curl"
  chmod +x "$mock_dir/curl"
  printf '%s' "$mock_dir"
}

# --- Test 1: returns full image ref when tag found with scan_status=passed ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.90.3-1","scan_status":"passed","digest":"sha256:abc123"}]}')
actual=$(PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" \
  "proj-id" "3.90.3-1" "registry.connect.redhat.com/sonatype/nxrm" 2>/dev/null)
run_test "returns full ref on success" \
  "registry.connect.redhat.com/sonatype/nxrm@sha256:abc123" "$actual"
rm -rf "$mock_dir"

# --- Test 2: exits 1 when scan_status is pending (simulates timeout with MAX_ATTEMPTS=1) ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.90.3-1","scan_status":"pending","digest":"sha256:abc123"}]}')
PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when scan_status is pending (timeout)" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 3: exits 1 when RH_API_TOKEN is empty ---
RH_API_TOKEN="" "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "tag" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when RH_API_TOKEN is empty" "1" "$actual_exit"

# --- Test 4: exits 1 when tag name is not in response ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.89.0-1","scan_status":"passed","digest":"sha256:old"}]}')
PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when requested tag not in response" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 5: picks correct tag when multiple tags present ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.89.0-1","scan_status":"passed","digest":"sha256:old"},{"name":"3.90.3-1","scan_status":"passed","digest":"sha256:new"}]}')
actual=$(PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null)
run_test "picks correct tag among multiple" "reg/img@sha256:new" "$actual"
rm -rf "$mock_dir"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

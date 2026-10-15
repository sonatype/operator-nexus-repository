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

# Creates a temporary directory with a mock `gh` that prints $1 (the PR state) and exits with $2
mock_gh() {
  mock_dir=$(mktemp -d "${TMPDIR:-/tmp}/mock-XXXXXX")
  printf '#!/bin/sh\nprintf '"'"'%%s\\n'"'"' '"'"'%s'"'"'\nexit %s\n' "$1" "${2:-0}" > "$mock_dir/gh"
  chmod +x "$mock_dir/gh"
  printf '%s' "$mock_dir"
}

mock_dir=$(mock_gh MERGED)
actual=$(PATH="$mock_dir:$PATH" MAX_ATTEMPTS=1 "$SCRIPT_DIR/wait-for-pr.sh" "https://x/pr/1" 2>/dev/null)
run_test "reports merged" "merged" "$actual"
rm -rf "$mock_dir"

mock_dir=$(mock_gh CLOSED)
actual=$(PATH="$mock_dir:$PATH" MAX_ATTEMPTS=1 "$SCRIPT_DIR/wait-for-pr.sh" "https://x/pr/1" 2>/dev/null)
run_test "reports closed" "closed" "$actual"
rm -rf "$mock_dir"

mock_dir=$(mock_gh OPEN)
actual=$(PATH="$mock_dir:$PATH" MAX_ATTEMPTS=1 "$SCRIPT_DIR/wait-for-pr.sh" "https://x/pr/1" 2>/dev/null)
actual_exit=$?
run_test "reports timeout while still open" "timeout" "$actual"
run_test "timeout exits 0" "0" "$actual_exit"
rm -rf "$mock_dir"

mock_dir=$(mock_gh "" 1)
PATH="$mock_dir:$PATH" MAX_ATTEMPTS=3 "$SCRIPT_DIR/wait-for-pr.sh" "https://x/pr/1" >/dev/null 2>&1
run_test "exits 1 when the PR cannot be read" "1" "$?"
rm -rf "$mock_dir"

"$SCRIPT_DIR/wait-for-pr.sh" >/dev/null 2>&1
run_test "exits 1 without arguments" "1" "$?"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

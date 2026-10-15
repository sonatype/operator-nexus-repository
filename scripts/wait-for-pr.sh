#!/bin/sh
# Polls a pull request until it is merged or closed, or the wait runs out.
# Usage: wait-for-pr.sh <prUrl>
# Output (stdout): merged | closed | timeout
# Exit: 0 once an outcome is known (including timeout), 1 on usage error or if the PR cannot be read.
# Env:
#   MAX_ATTEMPTS  - number of 60-second checks before timeout (default: 60)
#   GH_TOKEN      - token for the gh CLI

set -e

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s <prUrl>\n' "$0" >&2
  exit 1
fi

PR_URL="$1"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-60}"

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  if ! state=$(gh pr view "$PR_URL" --json state --jq .state 2>/dev/null); then
    printf 'ERROR: could not read pull request %s\n' "$PR_URL" >&2
    exit 1
  fi

  case "$state" in
    MERGED) printf 'merged\n'; exit 0 ;;
    CLOSED) printf 'closed\n'; exit 0 ;;
  esac

  attempt=$((attempt + 1))
  printf 'PR still open (check %d/%d). Red Hat certification usually takes 15-30 minutes. Retrying in 60s...\n' \
    "$attempt" "$MAX_ATTEMPTS" >&2
  [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 60
done

printf 'timeout\n'

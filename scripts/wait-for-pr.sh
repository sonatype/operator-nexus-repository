#!/bin/sh
# Polls a pull request until it is merged, closed or has a failed check, or the wait runs out.
# Usage: wait-for-pr.sh <prUrl>
# Output (stdout): merged | closed | failed | timeout
# Exit: 0 once an outcome is known (including timeout), 1 on usage error or if the PR cannot be read.
# Env:
#   MAX_ATTEMPTS  - number of 60-second checks before timeout (default: 120)
#   GH_TOKEN      - token for the gh CLI

set -e

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s <prUrl>\n' "$0" >&2
  exit 1
fi

PR_URL="$1"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-120}"

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  if ! json=$(gh pr view "$PR_URL" --json state,statusCheckRollup,labels 2>/dev/null); then
    printf 'ERROR: could not read pull request %s\n' "$PR_URL" >&2
    exit 1
  fi
  state=$(printf '%s' "$json" | jq -r '.state')

  case "$state" in
    MERGED) printf 'merged\n'; exit 0 ;;
    CLOSED) printf 'closed\n'; exit 0 ;;
  esac

  # Red Hat leaves a rejected PR open; pushing a fix (or commenting /pipeline restart
  # operator-hosted-pipeline) re-runs validation. Its bot reports failure with the
  # operator-hosted-pipeline/failed label, not a check run, so look at both. Stop early so the job
  # does not sit idle for the full wait.
  failed=$(printf '%s' "$json" | jq -r '[
    (.statusCheckRollup[]? |
      select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .state == "FAILURE" or .state == "ERROR")),
    (.labels[]? | select(.name == "operator-hosted-pipeline/failed"))] | length')
  if [ "$failed" -gt 0 ]; then
    printf 'failed\n'
    exit 0
  fi

  attempt=$((attempt + 1))
  printf 'PR still open (check %d/%d). Red Hat certification usually takes 35-60 minutes. Retrying in 60s...\n' \
    "$attempt" "$MAX_ATTEMPTS" >&2
  [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 60
done

printf 'timeout\n'

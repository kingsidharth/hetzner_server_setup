#!/usr/bin/env bash
# Mac runners: refuse untrusted triggers, then wait for the host-wide Apple build lock,
# so only one Apple job runs at a time across all repositories on this Mac.
set -Eeuo pipefail

"$(dirname "$0")/release-guard.sh"

is_worker() { [[ $(ps -o comm= -p "$1" 2>/dev/null) == *Runner.Worker ]]; }

# The Runner.Worker running this job owns the lock; once that process is gone (cancelled
# or crashed jobs never run the completed hook) the lock is stale.
worker=$PPID
while [[ $worker -gt 1 ]] && ! is_worker "$worker"; do
  worker=$(ps -o ppid= -p "$worker" | tr -d ' ')
done
is_worker "$worker" || { echo "::error::Couldn't find this job's Runner.Worker; refusing to run unlocked."; exit 1; }

lock=/tmp/ci-apple-build.lock
for i in $(seq 1080); do # up to 3 hours
  if mkdir "$lock" 2>/dev/null; then
    echo "$worker ${GITHUB_REPOSITORY:-?} ${GITHUB_RUN_ID:-?}" >"$lock/owner"
    exit 0
  fi
  read -r holder rest <"$lock/owner" 2>/dev/null || { sleep 2; continue; }
  if ! is_worker "$holder"; then
    # Rename first: only one waiter can win the move, so a stale lock is cleared exactly once.
    if mv "$lock" "$lock.stale.$$" 2>/dev/null; then
      echo "Cleared a stale Apple build lock from $rest"
      rm -rf "$lock.stale.$$"
    fi
    continue
  fi
  ((i == 1)) && echo "Waiting for another Apple build to finish: $rest"
  sleep 10
done
echo "::error::Timed out waiting for the Apple build lock"
exit 1

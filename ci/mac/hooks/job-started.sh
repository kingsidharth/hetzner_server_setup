#!/usr/bin/env bash
# Mac runners: refuse untrusted triggers, then wait for the host-wide Apple build lock,
# so only one Apple job runs at a time across all repositories on this Mac.
set -Eeuo pipefail

"$(dirname "$0")/release-guard.sh"

# The Runner.Worker running this job: the lock is stale once it's gone (cancelled or
# crashed jobs never run the completed hook).
worker=$PPID
while [[ $worker -gt 1 && $(ps -o comm= -p "$worker") != *Runner.Worker ]]; do
  worker=$(ps -o ppid= -p "$worker" | tr -d ' ')
done

lock=/tmp/ci-apple-build.lock
for i in $(seq 1080); do # up to 3 hours
  if mkdir "$lock" 2>/dev/null; then
    echo "$worker ${GITHUB_REPOSITORY:-?} ${GITHUB_RUN_ID:-?}" >"$lock/owner"
    exit 0
  fi
  read -r holder rest <"$lock/owner" 2>/dev/null || { sleep 2; continue; }
  if ! kill -0 "$holder" 2>/dev/null; then
    echo "Clearing a stale Apple build lock from $rest"
    rm -rf "$lock"
    continue
  fi
  ((i == 1)) && echo "Waiting for another Apple build to finish: $rest"
  sleep 10
done
echo "::error::Timed out waiting for the Apple build lock"
exit 1

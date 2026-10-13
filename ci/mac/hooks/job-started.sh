#!/usr/bin/env bash
# Mac runners: refuse untrusted triggers, then wait for the host-wide Apple build lock,
# so only one Apple job runs at a time across all repositories on this Mac.
set -Eeuo pipefail

"$(dirname "$0")/release-guard.sh"

lock=/tmp/ci-apple-build.lock
for _ in $(seq 1080); do # up to 3 hours
  if mkdir "$lock" 2>/dev/null; then
    echo "${GITHUB_REPOSITORY:-?} ${GITHUB_RUN_ID:-?}" >"$lock/owner"
    exit 0
  fi
  # A lock older than 4 hours belongs to a job that died without its completed hook.
  if [[ -n $(find "$lock" -maxdepth 0 -mmin +240 2>/dev/null) ]]; then
    rm -rf "$lock"
    continue
  fi
  [[ $_ == 1 ]] && echo "Waiting for another Apple build to finish: $(cat "$lock/owner" 2>/dev/null)"
  sleep 10
done
echo "::error::Timed out waiting for the Apple build lock"
exit 1

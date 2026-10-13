#!/usr/bin/env bash
# Releases the Apple build lock if this job holds it.
lock=/tmp/ci-apple-build.lock
read -r _ repo run <"$lock/owner" 2>/dev/null || exit 0
if [[ "$repo $run" == "${GITHUB_REPOSITORY:-?} ${GITHUB_RUN_ID:-?}" ]]; then
  rm -rf "$lock"
fi

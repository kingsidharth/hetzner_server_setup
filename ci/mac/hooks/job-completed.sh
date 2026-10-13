#!/usr/bin/env bash
# Releases the Apple build lock if this job holds it.
lock=/tmp/ci-apple-build.lock
if [[ $(cat "$lock/owner" 2>/dev/null) == "${GITHUB_REPOSITORY:-?} ${GITHUB_RUN_ID:-?}" ]]; then
  rm -rf "$lock"
fi

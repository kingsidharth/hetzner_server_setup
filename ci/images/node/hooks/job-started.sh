#!/usr/bin/env bash
# Runs before every job, inside the runner, before any workflow code.
# 1. A container serves one job: refuse any job that isn't under the first worker,
#    which the entrypoint records (as root) in /run/ci-guard/worker-pid.
# 2. Release-tier runners hold host secrets, so they only accept trusted triggers:
#    pushes, manual dispatches and published releases on the allowed refs.
#    Pull requests (including pull_request_target) are refused.
set -Eeuo pipefail
set -f # the ref patterns below are globs to match, not to expand

guard=/run/ci-guard/worker-pid
if [[ -f $guard ]]; then
  first=$(<"$guard")
  p=$$
  while [[ $p -gt 1 && $p != "$first" ]]; do
    p=$(awk '{print $4}' "/proc/$p/stat")
  done
  if [[ $p != "$first" ]]; then
    echo "::error::This runner container already ran a job; refusing a second one."
    exit 1
  fi
fi

[[ ${CI_TRUST:-check} == release ]] || exit 0

allowed_refs=${CI_RELEASE_REFS:-refs/heads/main refs/tags/v[0-9]*}
event=${GITHUB_EVENT_NAME:-}
ref=${GITHUB_REF:-}

case $event in
  push | workflow_dispatch | release) ;;
  *)
    echo "::error::Release-tier runner refuses '${event}' events. Use check-tier labels for this job."
    exit 1
    ;;
esac

for pattern in $allowed_refs; do
  # shellcheck disable=SC2053 # glob match is intended
  [[ $ref == $pattern ]] && exit 0
done
echo "::error::Release-tier runner refuses ref '${ref}'. Allowed: ${allowed_refs}"
exit 1

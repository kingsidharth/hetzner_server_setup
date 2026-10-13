#!/usr/bin/env bash
# Release-tier runners hold host secrets, so they only accept trusted triggers:
# pushes, manual dispatches and published releases on the allowed refs.
# Pull requests (including pull_request_target) are refused before any job code runs.
set -Eeuo pipefail

[[ ${CI_TRUST:-check} == release ]] || exit 0

allowed_refs=${CI_RELEASE_REFS:-refs/heads/main refs/tags/v*}
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

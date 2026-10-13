#!/usr/bin/env bash
# Registers a launchd-managed GitHub Actions runner on this Mac for one repository.
# Apple builds only: labels `apple,macos-arm64`, no default labels, release tier.
#   bash ci/mac/install-runner.sh OWNER/REPO
# Needs `gh` logged in as the repo owner. Re-running replaces the registration.
set -Eeuo pipefail

repo=${1:?usage: install-runner.sh OWNER/REPO}
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "bad repo '$repo'" >&2; exit 1; }
name=${repo#*/}
version=2.338.0
sha256=df4cebda25c86a886ed204e49fee63f5c2e7cec5f447b5c98440a826bbdf9df2
root=${CI_RUNNER_ROOT:-$HOME/actions-runner}
# The work dir stays on the internal disk by default: a LaunchAgent touching an external
# volume blocks on an invisible privacy (TCC) prompt until it's granted Full Disk Access.
# ".noindex" keeps Spotlight from indexing build output and caches (it doubled the Mac's CPU).
work_root=${CI_WORK_ROOT:-$root/_work.noindex}
dir=$root/$name
hooks=$root/_hooks
here=$(cd "$(dirname "$0")" && pwd)

cache_root=${CI_CACHE_ROOT:-$root/_cache.noindex}
mkdir -p "$dir" "$hooks" "$work_root/$name" "$cache_root"/{bun,electron,electron-builder,npm}
install -m 0755 "$here/hooks/job-started.sh" "$here/hooks/job-completed.sh" "$hooks/"
install -m 0755 "$here/../images/node/hooks/job-started.sh" "$hooks/release-guard.sh"

if [[ ! -x $dir/config.sh ]]; then
  tarball=$(mktemp -t actions-runner)
  curl -fsSL -o "$tarball" \
    "https://github.com/actions/runner/releases/download/v${version}/actions-runner-osx-arm64-${version}.tar.gz"
  echo "${sha256}  ${tarball}" | shasum -a 256 -c -
  tar -xzf "$tarball" -C "$dir"
  rm -f "$tarball"
fi

cd "$dir"
if [[ -f .service ]]; then ./svc.sh stop || true; ./svc.sh uninstall || true; fi
if [[ -f .runner ]]; then
  ACTIONS_RUNNER_INPUT_TOKEN=$(gh api -X POST "repos/$repo/actions/runners/remove-token" --jq .token) \
    ./config.sh remove
fi

# Token via the environment, never argv.
ACTIONS_RUNNER_INPUT_TOKEN=$(gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token) \
  ./config.sh --unattended --replace --url "https://github.com/$repo" \
  --name "$(hostname -s)-${name}-apple" --labels apple,macos-arm64 --no-default-labels \
  --work "$work_root/$name"

# The runner reads this file at start. Release tier: main / v* tags only, one Apple job at a time.
cat >.env <<EOF
CI_TRUST=release
ACTIONS_RUNNER_HOOK_JOB_STARTED=$hooks/job-started.sh
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$hooks/job-completed.sh
LANG=en_US.UTF-8
BUN_INSTALL_CACHE_DIR=$cache_root/bun
ELECTRON_CACHE=$cache_root/electron
ELECTRON_BUILDER_CACHE=$cache_root/electron-builder
npm_config_cache=$cache_root/npm
EOF
printf '%s\n' "$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" >.path

./svc.sh install
# launchd's default soft limit is 256 open files; bun, electron-builder and Xcode then stall
# forever on EMFILE (graceful-fs queues the opens). Raise it for the runner and its jobs.
plist=$(<.service) # svc.sh records the LaunchAgent plist path here
plutil -remove SoftResourceLimits "$plist" 2>/dev/null || true
plutil -insert SoftResourceLimits -json '{"NumberOfFiles": 65536}' "$plist"
./svc.sh start
echo "runner for $repo installed in $dir (work: $work_root/$name)"

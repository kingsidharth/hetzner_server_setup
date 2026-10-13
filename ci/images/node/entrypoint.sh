#!/usr/bin/env bash
# Container entrypoint for every CI image.
#   register  - read a registration token on stdin, configure the runner, save its state, exit
#   (default) - restore saved state, run the runner for exactly one job, then exit so
#               systemd recreates a fresh container for the next job
set -Eeuo pipefail

RUNNER_DIR=/opt/runner
STATE_DIR=/runner-state
STATE_FILES=(.runner .credentials .credentials_rsaparams)
DONE_FLAG=/tmp/ci-job-done

as_runner() {
  HOME=/home/runner USER=runner setpriv --reuid=1001 --regid=1001 --init-groups -- "$@"
}

# Volumes arrive owned by container root; hand the top level to the job user.
for dir in /cache/*; do
  [[ -d $dir ]] && chown 1001:1001 "$dir"
done

if [[ ${1:-} == register ]]; then
  read -r token
  as_runner "$RUNNER_DIR/config.sh" --unattended --replace --disableupdate \
    --url "https://github.com/${CI_REPO:?}" --token "$token" \
    --name "${CI_RUNNER_NAME:?}" --labels "${CI_LABELS:?}" --no-default-labels \
    --work /work
  # The files are private to the runner user and this root has no DAC override, so read them as runner.
  for f in "${STATE_FILES[@]}"; do
    as_runner cat "$RUNNER_DIR/$f" | install -m 0600 /dev/stdin "$STATE_DIR/$f"
  done
  echo "registered ${CI_RUNNER_NAME} on ${CI_REPO} with labels ${CI_LABELS}"
  exit 0
fi

for f in "${STATE_FILES[@]}"; do
  [[ -f $STATE_DIR/$f ]] || { echo "runner not registered (missing $f)" >&2; exit 78; }
  as_runner sh -c 'umask 077 && cat >"$1"' _ "$RUNNER_DIR/$f" <"$STATE_DIR/$f"
done

# Release-tier secrets: staged read-only by the host, copied to tmpfs readable only by the job user.
if [[ -d /run/ci-secrets-src ]]; then
  install -d -o 1001 -g 1001 -m 0700 /run/secrets/ci
  cp -R /run/ci-secrets-src/. /run/secrets/ci/
  chown -R 1001:1001 /run/secrets/ci
  chmod -R go-rwx /run/secrets/ci
fi

export ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/ci/hooks/job-started.sh
export ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/ci/hooks/job-completed.sh
export RUNNER_MANUALLY_TRAP_SIG=1
rm -f "$DONE_FLAG"

# Not via as_runner: $! must be run.sh itself. Without job control, background jobs (and
# everything they exec) ignore SIGINT, and the listener only shuts down cleanly on INT.
# So enable job control, then stop run.sh with TERM; it forwards INT to the listener.
set -m
HOME=/home/runner USER=runner setpriv --reuid=1001 --regid=1001 --init-groups -- "$RUNNER_DIR/run.sh" &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null || true' TERM INT

# One job per container: once the completed hook has fired and the worker has gone,
# stop the idle listener so the container exits and is recreated from the image.
while kill -0 "$pid" 2>/dev/null; do
  if [[ -e $DONE_FLAG ]] && ! pgrep -x Runner.Worker >/dev/null; then
    sleep 3
    if ! pgrep -x Runner.Worker >/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      break
    fi
  fi
  sleep 2
done
wait "$pid" || true

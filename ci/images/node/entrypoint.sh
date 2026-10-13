#!/usr/bin/env bash
# Container entrypoint for every CI image.
#   register  - read a registration token on stdin, configure the runner, save its state, exit
#   (default) - run the runner for exactly one job, then exit so systemd recreates a fresh
#               container. With CI_JITCONFIG set, the runner is a single-use JIT runner;
#               otherwise the saved registration is restored.
set -Eeuo pipefail

RUNNER_DIR=/opt/runner
STATE_DIR=/runner-state
STATE_FILES=(.runner .credentials .credentials_rsaparams)
GUARD_DIR=/run/ci-guard # root-owned; the job user can read but not write it

as_runner() {
  HOME=/home/runner USER=runner setpriv --reuid=1001 --regid=1001 --init-groups -- "$@"
}

# Volumes arrive owned by container root; hand the top level to the job user.
for dir in /cache/*; do
  [[ -d $dir ]] && chown 1001:1001 "$dir"
done

if [[ ${1:-} == register ]]; then
  read -r token || [[ -n ${token:-} ]]
  # Token via the environment, not argv, so it never shows up in a process listing.
  ACTIONS_RUNNER_INPUT_TOKEN=$token as_runner "$RUNNER_DIR/config.sh" --unattended --replace \
    --disableupdate --url "https://github.com/${CI_REPO:?}" \
    --name "${CI_RUNNER_NAME:?}" --labels "${CI_LABELS:?}" --no-default-labels --work /work
  # The files are private to the runner user and this root has no DAC override, so read them as runner.
  for f in "${STATE_FILES[@]}"; do
    as_runner cat "$RUNNER_DIR/$f" | install -m 0600 /dev/stdin "$STATE_DIR/$f"
  done
  echo "registered ${CI_RUNNER_NAME} on ${CI_REPO} with labels ${CI_LABELS}"
  exit 0
fi

# A JIT config is a credential: hand it over in the environment (readable only by the same
# uid or root), never in argv, which every host user can read through /proc.
jit=${CI_JITCONFIG:-}
unset CI_JITCONFIG
if [[ -z $jit ]]; then
  for f in "${STATE_FILES[@]}"; do
    [[ -f $STATE_DIR/$f ]] || { echo "runner not registered (missing $f)" >&2; exit 78; }
    as_runner sh -c 'umask 077 && cat >"$1"' _ "$RUNNER_DIR/$f" <"$STATE_DIR/$f"
  done
fi

# Release-tier secrets: staged read-only by the host, copied to tmpfs readable only by the job user.
if [[ -d /run/ci-secrets-src ]]; then
  # Copy while root still owns the directory (no DAC override), then hand it over.
  install -d -m 0700 /run/secrets/ci
  cp -R /run/ci-secrets-src/. /run/secrets/ci/
  chown -R 1001:1001 /run/secrets/ci
  chmod -R go-rwx /run/secrets/ci
fi
install -d -m 0755 "$GUARD_DIR"

export ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/ci/hooks/job-started.sh
export RUNNER_MANUALLY_TRAP_SIG=1

# Without job control, background jobs (and everything they exec) ignore SIGINT, and the
# listener only shuts down cleanly on INT. So enable job control, then stop run.sh with
# TERM; it forwards INT to the listener.
set -m
if [[ -n $jit ]]; then export ACTIONS_RUNNER_INPUT_JITCONFIG=$jit; fi
HOME=/home/runner USER=runner setpriv --reuid=1001 --regid=1001 --init-groups -- "$RUNNER_DIR/run.sh" &
pid=$!
unset ACTIONS_RUNNER_INPUT_JITCONFIG jit
# On stop, let a running job finish (the host allows 10 minutes); an idle runner stops at once.
stopping=
trap 'stopping=1' TERM INT

# One job per container, enforced from root by following the real process tree
# (run.sh > run-helper.sh > Runner.Listener > Runner.Worker). Job code can't insert itself
# there, and it can't touch the guard marker that makes the start hook refuse a second job.
child() { pgrep -P "$1" -x "$2" | head -n1; }
first_worker=
while kill -0 "$pid" 2>/dev/null; do
  helper=$(child "$pid" run-helper.sh || true)
  listener=${helper:+$(child "$helper" Runner.Listener || true)}
  worker=${listener:+$(child "$listener" Runner.Worker || true)}
  if [[ -n $worker && -z $first_worker ]]; then
    first_worker=$worker
    echo "$worker" >"$GUARD_DIR/worker-pid"
  elif [[ -n $worker && $worker != "$first_worker" ]]; then
    echo "second job in one container; killing it" >&2
    kill -KILL "$worker" "$listener" 2>/dev/null || true
    break
  elif [[ -z $worker && ( -n $first_worker || -n $stopping ) ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    break
  fi
  sleep 0.5
done

# Give the listener time to end its session cleanly, then make sure nothing is left.
for _ in $(seq 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
kill -KILL -- "-$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

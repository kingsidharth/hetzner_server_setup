# ci-platform: shared self-hosted CI

GitHub-hosted Actions is unavailable on this account, and runners on a personal
account register per repository. This directory makes that cheap: one host, one
config list, one image per toolchain, and a fresh container for every job.

| Host | Runs | How |
| --- | --- | --- |
| This server (Linux, x86_64) | PR checks, web/Convex deploys, Android, Windows cross-builds | `ci-runner@<instance>` systemd units, one container per job |
| Mac mini | Apple builds only (`apple` label) | launchd, see [`mac/`](mac/) |

## How it works

- A dedicated `ci-runner` user owns its own **rootless Docker**. Nothing else on
  the host uses it, so other Docker setups, users and services are untouched.
- Each line of `/etc/ci-platform/runners.conf` is a runner **instance**:
  repo, toolchain image, trust tier, CPU/memory limits, labels and secret scopes.
- `ci-runner@<instance>.service` starts a container from `ci-<image>:current`.
  The runner takes **one job**, then the container exits and systemd starts a
  fresh one. Registration persists in `/var/lib/ci-platform/state/<instance>`, so no
  long-lived GitHub admin token is needed on the host.
- Jobs run as an unprivileged user inside the container. Containers get no Docker
  socket, drop all capabilities except the few the entrypoint needs, and run with
  `no-new-privileges`. All CI together is capped at 10 cores and 48 GB via
  the `ci-runner` user slice.
- Images: `node` (runner, Node, Bun, gh) is the base; other images build `FROM ci-node:current`.
  `ci-images.timer` rebuilds them weekly with the latest runner, since runner self-update is off.

### Trust tiers

| | `check` | `release` |
| --- | --- | --- |
| Accepts | anything, including pull requests | only `push`, `workflow_dispatch`, `release` on `refs/heads/main` or `refs/tags/v*` |
| Host secrets | never | the scopes listed in its config line |
| Caches | `ci-cache-check-*` volumes | `ci-cache-release-*` volumes |

The release-tier guard is a runner `job-started` hook (`images/node/hooks/job-started.sh`).
A workflow cannot switch it off, so a PR that asks for release labels fails before
any of its code runs. Separate cache volumes per tier keep PR jobs from poisoning
what release builds install. Caches are shared across projects within a tier.

Self-hosted runners must never be attached to **public** repositories: anyone can
open a fork PR. Keep every repo in `runners.conf` private, with "Run workflows from
fork pull requests" off.

### Secrets layout

```
/etc/ci-secrets/                 root:root 0700
  <scope>/...                    e.g. morgwaith/android/upload.jks
```

When a release-tier container starts, its scopes are copied to a staging directory
owned by `ci-runner`, then mounted read-only. The entrypoint copies them to a tmpfs
at `/run/secrets/ci/<scope>/`, readable only by the job user. The staging copy is
deleted when the unit stops. Workflows must treat a missing file as "skip with a message".

## Install or update

```bash
git clone https://github.com/kingsidharth/hetzner_server_setup.git && cd hetzner_server_setup
sudo bash ci/install.sh
```

This is idempotent. It installs packages if missing, the `ci-runner` user and its
rootless Docker, the units, the images, then runs `ci-platform sync`.

## Add a project

1. Make sure the repository is **private**.
2. Add lines to `/etc/ci-platform/runners.conf` (see `runners.conf.example`).
   Typically one `check` node runner, plus `release` runners only for what it ships.
3. From any machine where `gh` is logged in as the repo owner, register each new instance:
   ```bash
   gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token \
     | ssh root@takida-ingest-01 ci-platform register INSTANCE
   ```
   `ci-platform sync` prints this command for every unregistered instance.
4. Put any release secrets in `/etc/ci-secrets/<scope>/` (root, 0700) and list the scope.
5. In workflows, use the instance labels, e.g. `runs-on: [takida, node]`. There are no
   default labels, so a bare `self-hosted` job is never picked up.

To remove an instance, delete its line, run `ci-platform sync`, and delete the
runner under the repo's Settings > Actions > Runners.

## Operate

```bash
ci-platform list                       # instances, registration, service state
journalctl -u ci-runner@INSTANCE -f    # runner log
ci-platform build-images --latest-runner
```

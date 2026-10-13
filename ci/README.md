# ci-platform: shared self-hosted CI

GitHub-hosted Actions is unavailable on this account, and runners on a personal
account register per repository. This directory makes that cheap: one host, one
config list, one image per toolchain, and a fresh container for every job.

| Host | Runs | How |
| --- | --- | --- |
| This server (Linux, x86_64) | PR checks, web/Convex deploys, Android, Windows cross-builds | `ci-runner@<instance>` systemd units, one container per job |
| Mac | Apple builds only (`apple` label) | launchd, see [`mac/`](mac/) |

## How it works

- A dedicated `ci-runner` user owns its own **rootless Docker**. Nothing else on
  the host uses it, so other Docker setups, users and services are untouched.
- Each line of `/etc/ci-platform/runners.conf` is a runner **instance**:
  repo, toolchain image, trust tier, CPU/memory limits, labels and secret scopes.
- `ci-runner@<instance>.service` starts a container from `ci-<image>:current`.
  It serves **one job**: root inside the container follows the real process tree and
  stops the listener as soon as the first job's worker exits, and the job-started hook
  refuses any second job. systemd then starts a fresh container.
- Jobs run as an unprivileged user inside the container. Containers get no Docker
  socket, drop all capabilities except the few the entrypoint needs, and run with
  `no-new-privileges`. All CI together is capped at 10 cores and 48 GB via the
  `ci-runner` user slice.
- **Egress**: `ci-egress.service` rejects traffic from `ci-runner` to private ranges,
  link-local (cloud metadata), the tailnet and this host's own addresses. Containers
  reach only the public internet.
- Images: `node` (runner, Node, Bun, gh) is the base; other images build `FROM ci-node:current`.
  `ci-images.timer` rebuilds them weekly with the latest runner, since runner self-update is off.

### Registration modes

| | Persistent (default) | JIT (recommended) |
| --- | --- | --- |
| Needs | a one-off registration token per instance | `/etc/ci-platform/github-token` (root 0600) |
| Credential lifetime | the runner's key lives as long as the registration | single use, gone after the job |
| Exposure | job code can read that key and impersonate the runner for later jobs | nothing reusable |

For JIT, create a fine-grained token at https://github.com/settings/personal-access-tokens/new:
resource owner = the repo owner, only the repositories in `runners.conf`, permission
**Administration: Read and write**. Save it to `/etc/ci-platform/github-token` and run
`ci-platform sync`. Every instance then mints a fresh JIT runner per container.

### Trust tiers

| | `check` | `release` |
| --- | --- | --- |
| Accepts | anything, including pull requests | only `push`, `workflow_dispatch`, `release` on `refs/heads/main` or `refs/tags/v[0-9]*` |
| Host secrets | never | the scopes listed in its config line |
| Caches | `ci-cache-check-*`, shared across projects | `ci-cache-release-<owner>_<repo>-*`, per project |

The release-tier guard is a runner `job-started` hook (`images/node/hooks/job-started.sh`).
A workflow cannot switch it off. Overriding `GITHUB_REF` / `GITHUB_EVENT_NAME` in the
job env doesn't fool it (tested), so a PR that asks for release labels fails before any
of its code runs.

Self-hosted runners must never be attached to **public** repositories: anyone can
open a fork PR. Keep every repo in `runners.conf` private, with "Run workflows from
fork pull requests" off.

**Known limits**:
- On GitHub Free, private repos have no branch or tag protection, so anyone with write
  access can push `main` or a `v*` tag and reach the release tier. Only give write
  access to people you'd trust with release secrets.
- Both tiers share one rootless daemon and one host user, so a container escape from a
  check job would reach release secrets. Separate users per tier would harden that.
- Containers on the daemon's bridge can reach each other (rootless Docker can't
  enforce `icc: false`). Runner containers don't listen on any ports.

### Secrets layout

```
/etc/ci-secrets/                 root:root 0700
  <scope>/...                    e.g. <project>/android/upload.jks
```

When a release-tier container starts, its scopes are copied to `/dev/shm/ci-platform`
(tmpfs, owned by `ci-runner`, 0700) and mounted read-only. The entrypoint copies them
to a tmpfs at `/run/secrets/ci/<scope>/`, readable only by the job user. The staging
copy is deleted when the unit stops. Workflows must treat a missing file as "skip
with a message".

## Install or update

```bash
git clone https://github.com/kingsidharth/hetzner_server_setup.git && cd hetzner_server_setup
sudo bash ci/install.sh
```

This is idempotent. It installs packages if missing, the `ci-runner` user and its
rootless Docker, the units, the egress rules and the images, then runs `ci-platform sync`.

## Add a project

1. Make sure the repository is **private**.
2. Add lines to `/etc/ci-platform/runners.conf` (see `runners.conf.example`).
   Typically one `check` node runner, plus `release` runners only for what it ships.
3. With JIT: add the repo to the fine-grained token, then run `ci-platform sync`. Done.
   Without JIT, register each new instance from any machine where `gh` is logged in as
   the repo owner (`ci-platform sync` prints this for every unregistered instance):
   ```bash
   gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token \
     | ssh root@<ci-host> ci-platform register INSTANCE
   ```
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

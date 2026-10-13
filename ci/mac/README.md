# Mac runners (Apple builds only)

Apple builds need macOS, Xcode and the signing identities in the login keychain, so
they can't run in the Linux containers. The Mac stays light: one idle listener per
repository (~20 MB), only for Apple jobs, one Apple job at a time.

```bash
bash ci/mac/install-runner.sh OWNER/REPO     # needs gh logged in as the repo owner
```

- Labels are exactly `apple,macos-arm64`, with no defaults. Jobs use `runs-on: [apple]`.
- The runner lives in `~/actions-runner/<repo>`, with its work dir in
  `~/actions-runner/_work.noindex/<repo>` (override with `CI_RUNNER_ROOT` / `CI_WORK_ROOT`).
  Keep it on the internal disk: a LaunchAgent touching an external volume hangs on an
  invisible privacy prompt unless the runner has Full Disk Access. Workflows should delete
  their build output at the end, since the internal disk is small. The same applies to
  caches: when `~/.bun/install/cache`, `~/Library/Caches/electron` or `~/.npm` are symlinks
  to an external volume, `bun install` and `electron-builder` hang inside `open()`. So the
  runner gets its own bun, Electron, electron-builder and npm caches in
  `~/actions-runner/_cache.noindex/`.
  launchd runs it through the runner's own `svc.sh` LaunchAgent, in the login session,
  so the keychain is available.
- **Release tier**: the shared guard (`../images/node/hooks/job-started.sh`) refuses
  everything except `push`, `workflow_dispatch` and `release` on `main` or `v[0-9]*`
  tags. Pull requests never run on the Mac. That matters because jobs run as your
  user, with your keychain.
- A host-wide lock (`/tmp/ci-apple-build.lock`) queues Apple jobs from different
  repositories, so they never compete for the Mac.

Remove a runner with `cd ~/actions-runner/<repo> && ./svc.sh uninstall`, then delete it
under the repo's Settings > Actions > Runners.

**Hardening idea**: run Apple CI as a separate macOS user whose keychain holds only the
Developer ID and distribution identities, so a compromised build can't reach your
home directory.

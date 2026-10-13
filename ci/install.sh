#!/usr/bin/env bash
# Installs or updates ci-platform on this host. Idempotent; run as root from a checkout:
#   bash ci/install.sh
# Leaves every other Docker setup, user and service on the host alone.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
CI_USER=ci-runner

echo "=== Packages"
need=()
for pkg in docker-ce docker-ce-rootless-extras uidmap slirp4netns jq curl; do
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed' || need+=("$pkg")
done
if ((${#need[@]})); then
  apt-get update
  apt-get install -y "${need[@]}"
fi

echo "=== Dedicated CI user with its own rootless Docker"
id "$CI_USER" >/dev/null 2>&1 || useradd --create-home --shell /usr/sbin/nologin "$CI_USER"
if ! grep -q "^${CI_USER}:" /etc/subuid; then
  start=$(awk -F: '{e=$2+$3; if (e>m) m=e} END {print (m>200000 ? m : 200000)}' /etc/subuid /etc/subgid)
  usermod --add-subuids "${start}-$((start + 65535))" --add-subgids "${start}-$((start + 65535))" "$CI_USER"
fi
CI_UID=$(id -u "$CI_USER")
loginctl enable-linger "$CI_USER"
for _ in $(seq 30); do [[ -S /run/user/$CI_UID/bus ]] && break; sleep 1; done

if [[ ! -e /etc/apparmor.d/rootlesskit ]]; then
  cat >/etc/apparmor.d/rootlesskit <<'EOF'
abi <abi/4.0>,
include <tunables/global>
profile rootlesskit /usr/bin/rootlesskit flags=(unconfined) {
  userns,
  include if exists <local/rootlesskit>
}
EOF
  apparmor_parser -r /etc/apparmor.d/rootlesskit
fi

as_ci() {
  runuser -u "$CI_USER" -- env XDG_RUNTIME_DIR="/run/user/$CI_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$CI_UID/bus" "$@"
}
if [[ ! -f /home/$CI_USER/.config/systemd/user/docker.service ]]; then
  (cd / && as_ci dockerd-rootless-setuptool.sh install)
fi
as_ci systemctl --user enable --now docker.service

echo "=== Host-wide ceiling for all CI containers (other workloads keep headroom)"
install -d "/etc/systemd/system/user-${CI_UID}.slice.d"
cat >"/etc/systemd/system/user-${CI_UID}.slice.d/50-ci-platform.conf" <<'EOF'
[Slice]
CPUQuota=1000%
MemoryHigh=40G
MemoryMax=48G
EOF

echo "=== Files"
install -d -m 0755 /etc/ci-platform /usr/local/lib/ci-platform
install -d -m 0700 /etc/ci-secrets
install -d -m 0755 /var/lib/ci-platform
install -d -o "$CI_USER" -g "$CI_USER" -m 0700 /var/lib/ci-platform/state /var/lib/ci-platform/run
if [[ ! -f /etc/ci-platform/runners.conf ]]; then
  grep '^#' "$here/runners.conf.example" >/etc/ci-platform/runners.conf
  chmod 0640 /etc/ci-platform/runners.conf # lists private repo names
fi
rm -rf /usr/local/lib/ci-platform/images
cp -R "$here/images" /usr/local/lib/ci-platform/images
install -m 0755 "$here/bin/ci-platform" "$here/bin/ci-egress" /usr/local/sbin/

sed "s/@CI_UID@/${CI_UID}/g" "$here/systemd/ci-runner@.service" >/etc/systemd/system/ci-runner@.service
install -m 0644 "$here/systemd/ci-images.service" "$here/systemd/ci-images.timer" \
  "$here/systemd/ci-egress.service" "$here/systemd/ci-egress-check.service" \
  "$here/systemd/ci-egress-check.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ci-images.timer
systemctl enable ci-egress.service
systemctl restart ci-egress.service
systemctl enable --now ci-egress-check.timer

echo "=== Images"
ci-platform build-images

echo "=== Runners"
ci-platform sync
ci-platform list

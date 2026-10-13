# Hetzner VPS Setup

Zero-public-port server setup: SSH via Tailscale, HTTP via Cloudflare Tunnel.

## Prerequisites
- Hetzner CX33+ with your SSH key selected at creation
- Tailscale auth key ([generate](https://login.tailscale.com/admin/settings/keys))
- Cloudflare Tunnel token ([create tunnel](https://one.dash.cloudflare.com/))

## Usage

```bash
# 1. As root on fresh server — installs Docker, creates deploy user, hardens SSH
curl -fsSL https://raw.githubusercontent.com/kingsidharth/hetzner_server_setup/main/1-setup.sh | bash

# ⚠️  Test deploy login in a NEW terminal before proceeding
# ssh deploy@<ip> -i ~/.ssh/id_hetz1

# 2. As deploy — clone and run
git clone https://github.com/kingsidharth/hetzner_server_setup.git ~/setup
cd ~/setup

bash 2-tailscale.sh --key tskey-auth-kXXXXX
# Verify at https://login.tailscale.com/admin/machines

bash 3-cloudflare.sh --token eyXXXXX
# Port 22 closed automatically. SSH now Tailscale-only.
```

## What you get

| Layer | Access via |
|-------|-----------|
| SSH | Tailscale only |
| HTTP/HTTPS | Cloudflare Tunnel only |
| Public ports | None |

## Stack installed
Docker, Docker Compose, UFW, fail2ban, 2GB swap

## Self-hosted CI (optional)
`sudo bash ci/install.sh` adds shared, containerised GitHub Actions runners for
private repositories. See [ci/README.md](ci/README.md).

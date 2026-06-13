#!/bin/bash
set -e

KEY=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --key) KEY="$2"; shift 2;;
    *) echo "Usage: bash 2-tailscale.sh --key tskey-auth-kXXX"; exit 1;;
  esac
done

if [ -z "$KEY" ]; then
  echo "Usage: bash 2-tailscale.sh --key tskey-auth-kXXX"
  exit 1
fi

echo "=== Installing Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --auth-key="$KEY" --ssh

echo ""
echo "=== Tailscale status ==="
tailscale status

echo ""
echo "=== DONE ==="
echo "Verify at https://login.tailscale.com/admin/machines"
echo "Test: ssh deploy@<tailscale-hostname>"
echo "Then: bash 3-cloudflare.sh --token <your-token>"

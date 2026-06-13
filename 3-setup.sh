#!/bin/bash
set -e

TOKEN=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --token) TOKEN="$2"; shift 2;;
    *) echo "Usage: bash 3-cloudflare.sh --token eyXXX"; exit 1;;
  esac
done

if [ -z "$TOKEN" ]; then
  echo "Usage: bash 3-cloudflare.sh --token eyXXX"
  exit 1
fi

echo "=== Installing Cloudflare Tunnel ==="
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared

echo "=== Registering tunnel ==="
sudo cloudflared service install "$TOKEN"

echo "=== Locking down port 22 ==="
sudo ufw delete allow 22/tcp
sudo ufw status

echo ""
echo "=== DONE ==="
echo "SSH: Tailscale only"
echo "HTTP: Cloudflare Tunnel only"
echo "Zero public ports."

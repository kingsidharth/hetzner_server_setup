#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root: curl -fsSL <raw-url> | bash"
  exit 1
fi

echo "=== Creating deploy user ==="
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
echo "deploy ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/deploy

echo "=== Installing packages ==="
apt-get update
apt-get install -y ufw fail2ban curl git unzip htop

echo "=== Installing Docker ==="
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
usermod -aG docker deploy

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "=== App directory ==="
mkdir -p /home/deploy/apps
chown -R deploy:deploy /home/deploy/apps

echo "=== Firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

echo "=== Harden SSH ==="
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

echo "=== Fail2ban ==="
systemctl enable fail2ban
systemctl start fail2ban

echo "=== Swap (2GB) ==="
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

echo ""
echo "=== DONE ==="
echo "Root login disabled. Test in a NEW terminal:"
echo "  ssh deploy@$(hostname -I | awk '{print $1}') -i ~/.ssh/id_hetz1"
echo ""
echo "Then: git clone <repo> ~/setup && cd ~/setup"
echo "Then: bash 2-tailscale.sh --key <your-key>"

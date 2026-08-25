#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this script as a normal sudo-capable user, not as root." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required." >&2
  exit 1
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ethtool networkd-dispatcher

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sudo bash
else
  echo "Tailscale already installed: $(tailscale version | head -1)"
fi

sudo systemctl enable --now tailscaled

echo
echo "Installed prerequisites and Tailscale."
echo "Next: authenticate this machine, for example:"
echo "  sudo tailscale up --hostname=<region-vpn>"

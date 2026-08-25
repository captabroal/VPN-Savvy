#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this script as a normal sudo-capable user, not as root." >&2
  exit 1
fi

for cmd in tailscale ethtool ip systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

if ! tailscale status >/dev/null 2>&1; then
  echo "This machine is not authenticated to Tailscale yet." >&2
  echo "Run: sudo tailscale up --hostname=<region-vpn>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo install -m 0644 "$SCRIPT_DIR/config/99-tailscale.conf" /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Keep the server's existing DNS behavior independent of Tailscale.
sudo tailscale set --accept-dns=false
sudo tailscale set --advertise-exit-node

OUT_IFACE="$(ip route show default | awk '{print $5}' | head -1)"
if [[ -z "$OUT_IFACE" ]]; then
  echo "Could not determine the default outbound interface." >&2
  exit 1
fi

echo "Outbound interface: $OUT_IFACE"

if sudo ethtool -k "$OUT_IFACE" 2>/dev/null | grep -q '^rx-udp-gro-forwarding:'; then
  sudo ethtool -K "$OUT_IFACE" rx-udp-gro-forwarding on rx-gro-list off
else
  echo "NIC does not expose rx-udp-gro-forwarding; skipping GRO optimization."
fi

sudo install -d -m 0755 /etc/networkd-dispatcher/routable.d
sudo install -m 0755 "$SCRIPT_DIR/hooks/50-tailscale" /etc/networkd-dispatcher/routable.d/50-tailscale
sudo systemctl enable --now networkd-dispatcher || true

echo
echo "Exit-node configuration applied."
echo "If your tailnet requires route approval, approve this machine as an exit node in the Tailscale admin console."
echo "OCI should also allow stateless UDP/41641 ingress for the best chance of direct peer connectivity."

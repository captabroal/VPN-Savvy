#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  -h|--help)
    echo "Usage: bash configure-exit-node.sh [--dry-run]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: bash configure-exit-node.sh [--dry-run]" >&2
    exit 2
    ;;
esac

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this script as a normal sudo-capable user, not as root." >&2
  exit 1
fi

for cmd in tailscale ethtool ip systemctl awk grep; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

if ! tailscale status >/dev/null 2>&1; then
  echo "This machine is not authenticated to Tailscale yet." >&2
  echo "Run: sudo tailscale up --hostname=<region-vpn>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Follow Tailscale's documented approach: ask the routing table which interface
# would carry normal internet traffic, with a default-route fallback.
OUT_IFACE="$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -z "$OUT_IFACE" ]]; then
  OUT_IFACE="$(ip route show default | awk '{print $5}' | head -1)"
fi
if [[ -z "$OUT_IFACE" ]]; then
  echo "Could not determine the default outbound interface." >&2
  exit 1
fi

if $DRY_RUN; then
  echo "DRY RUN: no changes will be made."
  echo "Outbound interface: $OUT_IFACE"
  echo
  echo "Would install:"
  echo "  $SCRIPT_DIR/config/99-tailscale.conf -> /etc/sysctl.d/99-tailscale.conf"
  echo "  $SCRIPT_DIR/hooks/50-tailscale -> /etc/networkd-dispatcher/routable.d/50-tailscale"
  echo
  echo "Would ensure:"
  echo "  net.ipv4.ip_forward = 1"
  echo "  net.ipv6.conf.all.forwarding = 1"
  echo "  tailscale accept-dns = false"
  echo "  exit-node advertisement enabled"
  echo "  rx-udp-gro-forwarding = on (if supported)"
  echo "  rx-gro-list = off (if supported)"
  echo "  networkd-dispatcher enabled and active"
  echo
  echo "Current state:"
  sysctl net.ipv4.ip_forward 2>&1 || true
  sysctl net.ipv6.conf.all.forwarding 2>&1 || true
  systemctl is-enabled tailscaled 2>&1 || true
  systemctl is-active tailscaled 2>&1 || true
  tailscale status 2>&1 || true
  echo
  echo "Current GRO state on $OUT_IFACE:"
  ethtool -k "$OUT_IFACE" 2>/dev/null | grep -E 'rx-udp-gro-forwarding|rx-gro-list' || true
  echo
  echo "Persistent files:"
  ls -l /etc/sysctl.d/99-tailscale.conf 2>&1 || true
  ls -l /etc/networkd-dispatcher/routable.d/50-tailscale 2>&1 || true
  exit 0
fi

sudo install -m 0644 "$SCRIPT_DIR/config/99-tailscale.conf" /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Keep this server's own DNS resolver independent of tailnet DNS settings.
sudo tailscale set --accept-dns=false
sudo tailscale set --advertise-exit-node

echo "Outbound interface: $OUT_IFACE"

if sudo ethtool -k "$OUT_IFACE" 2>/dev/null | grep -q '^rx-udp-gro-forwarding:'; then
  sudo ethtool -K "$OUT_IFACE" rx-udp-gro-forwarding on rx-gro-list off
else
  echo "NIC does not expose rx-udp-gro-forwarding; skipping GRO optimization."
fi

sudo install -d -m 0755 /etc/networkd-dispatcher/routable.d
sudo install -m 0755 "$SCRIPT_DIR/hooks/50-tailscale" /etc/networkd-dispatcher/routable.d/50-tailscale
sudo systemctl enable --now networkd-dispatcher

echo
echo "Exit-node configuration applied."
echo "If your tailnet requires route approval, approve this machine as an exit node in the Tailscale admin console."
echo "OCI should also allow stateless UDP/41641 ingress for the best chance of direct peer connectivity."

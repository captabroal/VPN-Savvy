#!/usr/bin/env bash
set -u

section() { printf '\n=== %s ===\n' "$1"; }

section "OS"
uname -m
uname -r
. /etc/os-release && echo "$PRETTY_NAME"

section "Resources"
echo "CPU: $(nproc)"
free -h | head -2
df -h /

section "Tailscale"
tailscale version 2>&1 || true
systemctl is-enabled tailscaled 2>&1 || true
systemctl is-active tailscaled 2>&1 || true
tailscale status 2>&1 || true
printf '\nTailscale IPs:\n'
tailscale ip 2>&1 || true

section "Netcheck"
tailscale netcheck 2>&1 || true

section "Forwarding"
sysctl net.ipv4.ip_forward 2>&1 || true
sysctl net.ipv6.conf.all.forwarding 2>&1 || true

section "Outbound interface"
OUT_IFACE="$(ip route show default | awk '{print $5}' | head -1)"
echo "${OUT_IFACE:-not found}"

if [[ -n "${OUT_IFACE:-}" ]]; then
  section "GRO"
  ethtool -k "$OUT_IFACE" 2>/dev/null | grep -E 'rx-udp-gro-forwarding|rx-gro-list' || true
  section "NIC counters"
  ip -s link show dev "$OUT_IFACE" || true
fi

section "Public IP"
curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null && echo || echo "Unable to query public IPv4"

section "DNS"
getent ahostsv4 tailscale.com | head -3 || true

section "Persistent files"
ls -l /etc/sysctl.d/99-tailscale.conf 2>&1 || true
ls -l /etc/networkd-dispatcher/routable.d/50-tailscale 2>&1 || true

section "Failed systemd units"
systemctl --failed --no-pager 2>&1 || true

section "Reboot required"
if [[ -e /var/run/reboot-required ]]; then
  cat /var/run/reboot-required
else
  echo "No"
fi

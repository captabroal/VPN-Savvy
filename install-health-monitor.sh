#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this script as a normal sudo-capable user, not as root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for f in \
  "$SCRIPT_DIR/scripts/health-check.sh" \
  "$SCRIPT_DIR/systemd/vpn-savvy-health.service" \
  "$SCRIPT_DIR/systemd/vpn-savvy-health.timer"; do
  [[ -f "$f" ]] || { echo "Missing required file: $f" >&2; exit 1; }
done

sudo install -d -m 0755 /opt/savvy/vpn/scripts /opt/savvy/vpn/logs
sudo install -m 0755 "$SCRIPT_DIR/scripts/health-check.sh" /opt/savvy/vpn/scripts/health-check.sh
sudo install -m 0644 "$SCRIPT_DIR/systemd/vpn-savvy-health.service" /etc/systemd/system/vpn-savvy-health.service
sudo install -m 0644 "$SCRIPT_DIR/systemd/vpn-savvy-health.timer" /etc/systemd/system/vpn-savvy-health.timer

sudo systemctl daemon-reload
sudo systemctl enable --now vpn-savvy-health.timer
sudo systemctl start vpn-savvy-health.service

echo
echo "VPN-Savvy health monitor installed."
echo "Timer status:"
systemctl status vpn-savvy-health.timer --no-pager || true

echo
echo "Next scheduled run:"
systemctl list-timers vpn-savvy-health.timer --no-pager || true

echo
echo "Latest health report:"
LATEST="$(ls -1t /opt/savvy/vpn/logs/health-*.log 2>/dev/null | head -1 || true)"
if [[ -n "$LATEST" ]]; then
  echo "$LATEST"
  tail -40 "$LATEST"
else
  echo "No health report found." >&2
  exit 1
fi

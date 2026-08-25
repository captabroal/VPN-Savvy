#!/usr/bin/env bash
set -uo pipefail

# VPN-Savvy periodic health check.
# This script performs useful diagnostics only. It does not change VPN,
# firewall, routing, SSH, OCI networking, or Tailscale configuration.

LOG_DIR="${VPN_SAVVY_LOG_DIR:-/opt/savvy/vpn/logs}"
RETENTION_DAYS="${VPN_SAVVY_LOG_RETENTION_DAYS:-30}"
STAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
SAFE_STAMP="${STAMP//:/-}"
LOG_FILE="$LOG_DIR/health-$SAFE_STAMP.log"

mkdir -p "$LOG_DIR"

# Keep a local report while also sending output to the systemd journal.
exec > >(tee -a "$LOG_FILE") 2>&1

section() { printf '\n=== %s ===\n' "$1"; }
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }

printf 'VPN-Savvy health report\n'
printf 'Time (UTC): %s\n' "$STAMP"
printf 'Host: %s\n' "$(hostname 2>/dev/null || echo unknown)"

section "Tailscale service"
if systemctl is-active --quiet tailscaled; then
  pass "tailscaled active"
else
  warn "tailscaled is not active"
fi
if systemctl is-enabled --quiet tailscaled 2>/dev/null; then
  pass "tailscaled enabled at boot"
else
  warn "tailscaled is not enabled at boot"
fi
if command -v tailscale >/dev/null 2>&1; then
  tailscale version 2>&1 || true
  tailscale status 2>&1 || true
else
  warn "tailscale command not found"
fi

section "Tailscale netcheck"
if command -v tailscale >/dev/null 2>&1; then
  tailscale netcheck 2>&1 || warn "tailscale netcheck returned an error"
fi

section "IP forwarding"
IPV4_FWD="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unknown)"
IPV6_FWD="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unknown)"
printf 'IPv4 forwarding: %s\n' "$IPV4_FWD"
printf 'IPv6 forwarding: %s\n' "$IPV6_FWD"
[[ "$IPV4_FWD" == "1" ]] && pass "IPv4 forwarding enabled" || warn "IPv4 forwarding is not enabled"
[[ "$IPV6_FWD" == "1" ]] && pass "IPv6 forwarding enabled" || warn "IPv6 forwarding is not enabled"

section "Outbound interface and GRO"
OUT_IFACE="$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -z "$OUT_IFACE" ]]; then
  OUT_IFACE="$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)"
fi
if [[ -n "$OUT_IFACE" ]]; then
  printf 'Outbound interface: %s\n' "$OUT_IFACE"
  if command -v ethtool >/dev/null 2>&1; then
    ethtool -k "$OUT_IFACE" 2>/dev/null | grep -E 'rx-udp-gro-forwarding|rx-gro-list' || warn "GRO fields unavailable"
  else
    warn "ethtool command not found"
  fi
else
  warn "could not determine outbound interface"
fi

section "Public IPv4"
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "$PUBLIC_IP" ]]; then
    printf '%s\n' "$PUBLIC_IP"
  else
    warn "unable to determine public IPv4"
  fi
else
  warn "curl command not found"
fi

section "DNS"
if getent ahostsv4 tailscale.com >/dev/null 2>&1; then
  pass "DNS resolution working"
  getent ahostsv4 tailscale.com 2>/dev/null | head -3 || true
else
  warn "DNS resolution failed"
fi

section "Outbound connectivity"
if command -v curl >/dev/null 2>&1; then
  HTTP_CODE="$(curl -4sS -o /dev/null --max-time 15 -w '%{http_code}' https://tailscale.com 2>/dev/null || true)"
  if [[ "$HTTP_CODE" =~ ^[23][0-9][0-9]$ ]]; then
    pass "HTTPS connectivity working (HTTP $HTTP_CODE)"
  else
    warn "HTTPS connectivity check returned '${HTTP_CODE:-no response}'"
  fi
fi

section "Failed systemd units"
FAILED_COUNT="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
if [[ "$FAILED_COUNT" == "0" ]]; then
  pass "no failed systemd units"
else
  warn "$FAILED_COUNT failed systemd unit(s)"
  systemctl --failed --no-pager 2>&1 || true
fi

section "NIC counters"
if [[ -n "${OUT_IFACE:-}" ]]; then
  ip -s link show dev "$OUT_IFACE" 2>&1 || true
else
  warn "NIC counters unavailable because outbound interface was not found"
fi

section "Reboot required"
if [[ -e /var/run/reboot-required ]]; then
  warn "system reboot required"
  cat /var/run/reboot-required 2>/dev/null || true
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
  pass "no reboot currently required"
fi

section "Retention"
# Delete only this monitor's own timestamped logs older than the configured age.
find "$LOG_DIR" -type f -name 'health-*.log' -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
printf 'Retention: %s days\n' "$RETENTION_DAYS"
printf 'Report: %s\n' "$LOG_FILE"

printf '\nHealth check complete.\n'

#!/usr/bin/env bash
set -u

PASS=0
WARN=0
FAIL=0

pass() { printf 'PASS  %s\n' "$*"; PASS=$((PASS+1)); }
warn() { printf 'WARN  %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
section() { printf '\n=== %s ===\n' "$1"; }

section "Safety"
echo "Read-only audit. This script does not use sudo and does not modify configuration."

section "Platform"
printf 'Architecture: '; uname -m
printf 'Kernel:       '; uname -r
if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "OS:           $PRETTY_NAME"; fi
printf 'CPU count:    '; nproc
free -h | head -2
df -h /

section "Tailscale service"
if command -v tailscale >/dev/null 2>&1; then
  tailscale version 2>&1 || true
else
  fail "tailscale command is not installed"
fi

[[ "$(systemctl is-enabled tailscaled 2>/dev/null || true)" == "enabled" ]] && pass "tailscaled enabled at boot" || fail "tailscaled is not enabled"
[[ "$(systemctl is-active tailscaled 2>/dev/null || true)" == "active" ]] && pass "tailscaled active" || fail "tailscaled is not active"

tailscale status 2>&1 || true

section "Exit-node advertisement"
if tailscale debug prefs 2>/dev/null | grep -q '0.0.0.0/0'; then
  pass "IPv4 default route is advertised"
else
  warn "Could not confirm IPv4 exit-node advertisement from tailscale debug prefs"
fi
if tailscale debug prefs 2>/dev/null | grep -q '::/0'; then
  pass "IPv6 default route is advertised"
else
  warn "Could not confirm IPv6 exit-node advertisement from tailscale debug prefs"
fi

section "IP forwarding"
V4="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo unknown)"
V6="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo unknown)"
[[ "$V4" == "1" ]] && pass "IPv4 forwarding enabled" || fail "IPv4 forwarding is $V4"
[[ "$V6" == "1" ]] && pass "IPv6 forwarding enabled" || fail "IPv6 forwarding is $V6"

if [[ -r /etc/sysctl.d/99-tailscale.conf ]]; then
  grep -qE '^\s*net\.ipv4\.ip_forward\s*=\s*1\s*$' /etc/sysctl.d/99-tailscale.conf && pass "IPv4 forwarding persisted" || warn "IPv4 forwarding not found in expected persistent file"
  grep -qE '^\s*net\.ipv6\.conf\.all\.forwarding\s*=\s*1\s*$' /etc/sysctl.d/99-tailscale.conf && pass "IPv6 forwarding persisted" || warn "IPv6 forwarding not found in expected persistent file"
else
  warn "/etc/sysctl.d/99-tailscale.conf not present"
fi

section "Outbound interface and GRO"
OUT_IFACE="$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -z "$OUT_IFACE" ]]; then OUT_IFACE="$(ip route show default | awk '{print $5}' | head -1)"; fi
if [[ -z "$OUT_IFACE" ]]; then
  fail "Could not determine outbound interface"
else
  echo "Outbound interface: $OUT_IFACE"
  GRO="$(ethtool -k "$OUT_IFACE" 2>/dev/null | grep -E 'rx-udp-gro-forwarding|rx-gro-list' || true)"
  echo "$GRO"
  if echo "$GRO" | grep -qE '^rx-udp-gro-forwarding: on'; then pass "rx-udp-gro-forwarding is on"; else warn "rx-udp-gro-forwarding is not confirmed on"; fi
  if echo "$GRO" | grep -qE '^rx-gro-list: off'; then pass "rx-gro-list is off"; else warn "rx-gro-list is not confirmed off"; fi
fi

section "GRO persistence"
HOOK=/etc/networkd-dispatcher/routable.d/50-tailscale
if [[ -f "$HOOK" ]]; then
  [[ -x "$HOOK" ]] && pass "networkd-dispatcher hook is executable" || fail "networkd-dispatcher hook is not executable"
  grep -q 'rx-udp-gro-forwarding on' "$HOOK" && pass "hook enables UDP GRO forwarding" || warn "hook does not contain expected UDP GRO command"
  grep -q 'rx-gro-list off' "$HOOK" && pass "hook disables rx-gro-list" || warn "hook does not contain expected rx-gro-list command"
else
  warn "$HOOK not present"
fi
[[ "$(systemctl is-enabled networkd-dispatcher 2>/dev/null || true)" == "enabled" ]] && pass "networkd-dispatcher enabled" || warn "networkd-dispatcher not enabled"

section "Connectivity"
echo "Public IPv4: $(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || echo unavailable)"
tailscale netcheck 2>&1 || true

section "NIC counters"
if [[ -n "${OUT_IFACE:-}" ]]; then ip -s link show dev "$OUT_IFACE" 2>&1 || true; fi

section "System health"
systemctl --failed --no-pager 2>&1 || true
if [[ -e /var/run/reboot-required ]]; then warn "reboot required"; else pass "no reboot currently required"; fi

section "Summary"
echo "PASS=$PASS WARN=$WARN FAIL=$FAIL"
if (( FAIL > 0 )); then
  echo "RESULT: ATTENTION REQUIRED"
  exit 1
elif (( WARN > 0 )); then
  echo "RESULT: HEALTHY WITH WARNINGS"
  exit 0
else
  echo "RESULT: HEALTHY"
  exit 0
fi

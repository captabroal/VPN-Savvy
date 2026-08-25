# Optional health monitor

VPN-Savvy includes an optional systemd-based health monitor for long-lived exit nodes.

It is **monitoring only**. It does not intentionally generate CPU, memory, or network load and should not be treated as a mechanism for defeating cloud-provider idle-reclamation policies.

## Install

From a cloned repository:

```bash
bash install-health-monitor.sh
```

The installer creates:

- `/opt/savvy/vpn/scripts/health-check.sh`
- `/etc/systemd/system/vpn-savvy-health.service`
- `/etc/systemd/system/vpn-savvy-health.timer`

It also creates/uses:

- `/opt/savvy/vpn/logs/`

## Schedule

The timer runs at six-hour intervals:

```text
00:00
06:00
12:00
18:00
```

with up to five minutes of randomized delay.

`Persistent=true` means a missed run can be triggered after the system comes back online.

## Checks

Each run records useful diagnostics including:

- `tailscaled` active/enabled state
- Tailscale version and peer status
- `tailscale netcheck`
- IPv4 and IPv6 forwarding
- dynamically detected outbound interface
- UDP GRO forwarding state
- public IPv4
- DNS resolution
- outbound HTTPS connectivity
- failed systemd units
- physical NIC counters including errors/drops
- reboot-required state

## Logs

Timestamped logs are stored under:

```text
/opt/savvy/vpn/logs/health-*.log
```

Logs older than 30 days are removed by the monitor itself.

Override the defaults when running the script manually with:

```bash
VPN_SAVVY_LOG_DIR=/path/to/logs VPN_SAVVY_LOG_RETENTION_DAYS=14 bash scripts/health-check.sh
```

## Inspect the timer

```bash
systemctl status vpn-savvy-health.timer --no-pager
systemctl list-timers vpn-savvy-health.timer --no-pager
```

Run an immediate check:

```bash
sudo systemctl start vpn-savvy-health.service
```

View the latest report:

```bash
LATEST=$(ls -1t /opt/savvy/vpn/logs/health-*.log | head -1)
cat "$LATEST"
```

## Remove

```bash
sudo systemctl disable --now vpn-savvy-health.timer
sudo rm -f /etc/systemd/system/vpn-savvy-health.timer
sudo rm -f /etc/systemd/system/vpn-savvy-health.service
sudo systemctl daemon-reload
```

Removing the timer does not remove Tailscale or modify exit-node configuration.

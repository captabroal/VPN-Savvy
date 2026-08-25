# Recovery and rebuild

The purpose of this repository is to make the exit node disposable and reproducible.

## If the VM is lost

1. Create a new Ubuntu VM in the desired region.
2. Configure the OCI public subnet, Internet Gateway route, SSH access, and UDP/41641 ingress.
3. Clone this repository.
4. Run `./install.sh`.
5. Authenticate with `sudo tailscale up --hostname=<region-vpn>`.
6. Run `./configure-exit-node.sh`.
7. Approve the exit node in the Tailscale admin console if required.
8. Run `./verify.sh`.
9. Test from a client before removing any fallback access.

## If Tailscale stops working

Check:

```bash
systemctl status tailscaled --no-pager
tailscale status
tailscale netcheck
```

Then verify forwarding:

```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
```

Both should normally be `1` for an exit node.

Check the physical outbound interface and GRO settings:

```bash
IFACE=$(ip route show default | awk '{print $5}' | head -1)
ethtool -k "$IFACE" | grep -E 'rx-udp-gro-forwarding|rx-gro-list'
```

For supported interfaces, the intended state is:

```text
rx-udp-gro-forwarding: on
rx-gro-list: off
```

## If clients use DERP instead of direct connectivity

Verify:

- OCI UDP/41641 ingress exists and is stateless;
- the guest firewall does not block it;
- `tailscale netcheck` reports UDP connectivity;
- the client and server are both online.

Use `tailscale status` on the client to distinguish `direct` from `relay` paths.

## If a public IP changes

A new public IP can change geolocation and service compatibility. Re-test the IP against the intended regional services before relying on it.

## Secrets

Never back up `/var/lib/tailscale/` or private SSH keys into this repository. Treat rebuilds as fresh machine enrollment unless you have a deliberate secure state-backup process outside GitHub.

# VPN-Savvy

A small, reproducible setup for running a **Tailscale exit node on an Oracle Cloud Infrastructure (OCI) Ubuntu VM**.

The project is designed for personal, region-specific internet egress from laptops, phones, and TV devices while keeping the server configuration simple, auditable, and easy to rebuild.

## What this configures

- Official Tailscale client on Ubuntu
- Linux IPv4 and IPv6 forwarding
- Tailscale exit-node advertisement
- Server-side DNS kept independent of Tailscale (`--accept-dns=false`)
- Tailscale-recommended UDP GRO forwarding optimization for Linux exit nodes
- Persistent GRO settings using `networkd-dispatcher`
- Verification script for service health, routing, forwarding, GRO, public IP, and Tailscale connectivity
- OCI networking guidance for direct UDP connectivity on port `41641`

## What this does **not** contain

This public repository intentionally contains **no live infrastructure secrets or machine-specific identity data**. Do not commit:

- SSH private keys
- Tailscale auth keys, OAuth tokens, or `/var/lib/tailscale/`
- OCI API keys, tenancy/user OCIDs, or credentials
- Cloud-init secrets
- Shell history or logs containing credentials
- Private DNS names, private application credentials, or account identifiers

See [SECURITY.md](SECURITY.md).

## Tested design

The configuration targets a recent Ubuntu LTS release on OCI ARM64 or x86_64 VMs. Tailscale recommends Linux kernel **6.2 or later** for its current transport-layer offload performance improvements.

The intended path is:

```text
Client device
    |
    | Tailscale / WireGuard
    v
OCI Ubuntu VM (exit node)
    |
    v
Public internet
```

A direct Tailscale peer connection is preferred over DERP relay for lower latency and higher throughput.

## Quick start

### 1. Prepare OCI networking

Create the Ubuntu VM with internet access and keep SSH reachable until Tailscale access has been independently tested.

Then add a **stateless ingress rule** in the OCI security list used by the VM:

```text
Source:           0.0.0.0/0
Protocol:         UDP
Destination port: 41641
Stateless:        Yes
```

See [docs/oci.md](docs/oci.md) for the complete OCI checklist.

### 2. Clone the repository

```bash
git clone https://github.com/captabroal/VPN-Savvy.git
cd VPN-Savvy
```

### 3. Install prerequisites and Tailscale

```bash
bash install.sh
```

### 4. Authenticate the VM to your tailnet

Choose a meaningful node name for the region, for example `mumbai-vpn` or `turin-vpn`:

```bash
sudo tailscale up --hostname=mumbai-vpn
```

Open the authentication URL shown by Tailscale and complete sign-in.

### 5. Configure the exit node

```bash
bash configure-exit-node.sh
```

Then approve the machine for **Use as exit node** in the Tailscale admin console if your tailnet requires approval.

### 6. Verify

```bash
bash verify.sh
```

From a client device, select the new exit node and confirm:

```bash
tailscale status
```

The best case is a peer line containing something similar to:

```text
direct <public-ip>:41641
```

Then confirm your client-facing public IP is the OCI VM's public IP.

## Files

```text
.
├── README.md
├── LICENSE
├── SECURITY.md
├── .gitignore
├── install.sh
├── configure-exit-node.sh
├── verify.sh
├── config/
│   └── 99-tailscale.conf
├── hooks/
│   └── 50-tailscale
└── docs/
    ├── oci.md
    └── recovery.md
```

## Performance philosophy

The scripts intentionally avoid generic "VPN speed tweak" recipes. They apply only the Linux exit-node optimization currently recommended by Tailscale:

```bash
ethtool -K <outbound-interface> rx-udp-gro-forwarding on rx-gro-list off
```

No automatic BBR changes, MTU guessing, custom kernels, IRQ pinning, or broad sysctl tuning are applied.

## Important operational notes

- Do not remove public SSH until Tailscale administration has been proven from another device.
- Do not make the OCI VM itself use another exit node.
- An exit node does not need to advertise the OCI private subnet unless you explicitly want subnet-routing functionality.
- If the machine is also an application server, baseline its DNS, firewall, listening ports, and application health before adding Tailscale, then verify them again afterward.
- Tailscale connector/exit-node key expiry can make the advertised route unreachable. For long-lived infrastructure, review the machine's key-expiry policy in the Tailscale admin console.

## Official references

- Tailscale exit nodes: https://tailscale.com/docs/features/exit-nodes
- Exit-node setup: https://tailscale.com/docs/features/exit-nodes/how-to/setup
- Performance best practices: https://tailscale.com/docs/reference/best-practices/performance
- Tailscale on Oracle Cloud: https://tailscale.com/docs/install/cloud/oracle-cloud
- OCI networking documentation: https://docs.oracle.com/en-us/iaas/Content/Network/home.htm

## License

MIT — see [LICENSE](LICENSE).

# OCI setup

This project assumes an Ubuntu VM with normal internet access in Oracle Cloud Infrastructure.

## Minimum network requirements

The VM should have:

- a public IPv4 address if you want to administer it directly from the internet
- a route for `0.0.0.0/0` through an OCI Internet Gateway
- SSH ingress while initial setup is in progress

Keep public SSH available until Tailscale administration has been tested from another device.

## Direct Tailscale connectivity

For the best chance of a direct peer connection rather than DERP relay, add a **stateless ingress rule** to the OCI security list or NSG protecting the VM:

```text
Source type:      CIDR
Source:           0.0.0.0/0
IP protocol:      UDP
Source port:      Any
Destination port: 41641
Stateless:        Yes
Description:      Tailscale direct connectivity
```

Do not open unrelated ports.

## Public IP considerations

An OCI public IP is a datacenter IP. Streaming, banking, commerce, and other services may classify or block datacenter ranges differently from residential networks.

Before depending on a regional exit node, verify:

1. the public IP geolocates to the intended country in multiple databases;
2. the target services actually work;
3. the client uses the exit node and exposes the VM's public IP externally.

## OCI VM size

Tailscale itself is lightweight. For a personal exit node, CPU/network capacity generally matters more than RAM or disk size. Choose a shape based on expected throughput and any other applications sharing the VM.

## Existing application servers

If adding Tailscale to a VM that already hosts applications:

- capture existing DNS, routes, firewall rules, listening ports, and service health first;
- avoid advertising private subnets unless explicitly required;
- keep the server's DNS independent with `tailscale set --accept-dns=false` when appropriate;
- verify every pre-existing service after the networking changes.

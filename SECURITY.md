# Security

This repository is intentionally safe to publish. It should contain only generic deployment logic and documentation.

## Never commit

- SSH private keys or private-key material
- Tailscale auth keys, OAuth tokens, session state, or `/var/lib/tailscale/`
- OCI API private keys, tenancy/user identifiers when not necessary, or credentials
- passwords, recovery codes, cookies, or bearer tokens
- cloud-init files containing secrets
- application `.env` files containing credentials
- terminal history or diagnostic logs containing sensitive values

## Public IP addresses

A public IP address is not an authentication secret, but machine-specific public IPs are intentionally omitted from this project so the repository remains reusable and does not unnecessarily disclose live infrastructure.

## Before publishing changes

Review the staged diff for:

- private key headers such as `BEGIN OPENSSH PRIVATE KEY`
- `tskey-` strings
- OAuth or bearer tokens
- OCI credential material
- email addresses, home paths, and machine-specific account identifiers
- copied command output containing secrets

## Reporting a security issue

If you find a credential or private key committed to this repository, revoke/rotate the credential first. Removing it from the latest commit alone is not sufficient because Git history may retain it.

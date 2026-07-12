---
name: linux-tailscale-networking
description: "Configure and troubleshoot Tailscale on Linux with iptables/nftables, subnet routing, exit nodes, Tailscale Serve, and locally bound services."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [linux, tailscale, iptables, nftables, exit-node, subnet-router, serve, dashboard]
---

# Linux Tailscale networking

Use when a Linux host must expose services over Tailscale, act as a subnet router or exit node, or when iptables/nftables rules appear to conflict with Tailscale.

## Verify first

1. Inspect interfaces and routes:
   ```bash
   ip -br addr
   ip route
   tailscale status
   tailscale debug prefs
   ```
2. Inspect the actual loaded firewall, not only a persistence file:
   ```bash
   sudo iptables-save
   sudo iptables -t nat -S
   sudo nft list ruleset
   ```
   On Ubuntu, `iptables v1.8.x (nf_tables)` means the iptables command is an nftables frontend. Do not mix `iptables-legacy` with the nft backend.
3. Check forwarding:
   ```bash
   sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
   ```

## Rule interpretation

Tailscale commonly installs `ts-input`, `ts-forward`, and `ts-postrouting` chains. Rules accepting `tailscale0`, marking Tailscale-forwarded traffic, and MASQUERADEing marked traffic are expected.

An unconditional rule such as:

```text
-A POSTROUTING -j MASQUERADE
```

is broader than the Tailscale rule and NATs all outbound traffic. Treat it as a manual/persistence-file candidate; do not remove it until checking whether general NAT is intentionally required. Compare the saved file with the kernel state before changing anything:

```bash
sudo iptables-save | diff -u /etc/iptables/rules.v4 -
```

## Tailscale roles

- **Remote access to the host:** `tailscale0` is enough; verify the service is listening on the Tailscale address or all addresses.
- **Subnet router:** advertise only the intended LAN CIDR, e.g. `sudo tailscale set --advertise-routes=10.0.0.0/24`, then approve the route in the admin console.
- **Exit node:** advertise `0.0.0.0/0` and `::/0`, e.g. `sudo tailscale set --advertise-exit-node`, then approve/select the node. This is distinct from advertising a private subnet.

## Localhost services and Tailscale Serve

A service bound to `127.0.0.1:PORT` cannot normally be reached at `TAILSCALE_IP:PORT`. Prefer Tailscale Serve as a local-to-tailnet reverse proxy:

```bash
sudo tailscale serve --bg PORT
tailscale serve status
```

Some applications validate the HTTP `Host` header. Tailscale Serve sends the tailnet DNS hostname, which a localhost-only Host validator may reject. For Hermes Dashboard, bind with authentication to `0.0.0.0` when using Tailscale Serve:

```bash
export HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
read -rsp 'Dashboard password: ' HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
printf '\n'
hermes dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build
sudo tailscale serve --bg 9119
```

Do not rely on `--insecure` to disable auth on current Hermes releases; non-loopback binds require an auth provider. Keep the host firewall restricted to `tailscale0` where appropriate.

## Pitfalls

- Adding an iptables ACCEPT rule does not fix a service bound only to `127.0.0.1`.
- A direct bind to a specific Tailscale IP can still fail through Tailscale Serve because the proxy Host header is the `.ts.net` hostname; use `0.0.0.0` plus authentication for apps that require exact Host matching.
- Do not expose an administrative dashboard without authentication merely because the port is intended for a tailnet.
- Do not infer the active firewall from `/etc/iptables/rules.v4`; verify the running kernel rules.
- `tailscale serve` and direct port access are different paths. Test the URL returned by `tailscale serve status` separately from `http://TAILSCALE_IP:PORT`.

## Minimal checks

```bash
ss -lntp | grep ':PORT'
curl -fsS http://127.0.0.1:PORT/ >/dev/null
curl -I http://TAILSCALE_IP:PORT/
tailscale serve status
```

For changes, preserve rollback commands and verify the exact listening address, route advertisement, firewall counters, and client-side connectivity.
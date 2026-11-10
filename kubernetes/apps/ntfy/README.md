# ntfy

ntfy serves `https://ntfy.unbeholden.dev` on the private Traefik listener at
`192.168.4.200`, with its own Let's Encrypt certificate from the DNS-01 issuer.
AdGuard rewrites the name to `.200`, so LAN and tailnet clients reach the
cluster directly. Public DNS points at Giran, which proxies over the tailnet to
`.200`, so the phone needs no Tailscale away from home.

The whole `server.yml` lives in the SOPS Secret `config.sops.yaml`, including
users, topic grants and tokens. Anonymous access is denied. `admin` reads and
writes every topic; `apps` may only publish, to any topic, and every publishing
service uses one of its tokens. Edit with `sops edit kubernetes/apps/ntfy/config.sops.yaml`; hash a
new password with `ntfy user hash` and make a token with `ntfy token generate`.
ntfy reconciles the provisioned users on start, so roll the pod after a change:
`kubectl -n ntfy rollout restart deployment/ntfy`.

The message cache and user database sit on a local PV on `talos-worker-01`.
Losing it loses only cached messages; Git recreates the accounts.

## Prepare storage

Before merging, with the working `TALOSCONFIG`:

```sh
talosctl --nodes 192.168.4.133 patch mc --patch @kubernetes/apps/ntfy/worker-volume.patch.yaml
talosctl --nodes 192.168.4.133 get volumestatus u-ntfy
talosctl --nodes 192.168.4.133 get mountstatus u-ntfy
```

## Deploy and test

```sh
flux reconcile kustomization flux-system --with-source
kubectl -n ntfy wait --for=condition=Ready certificate/ntfy --timeout=20m
kubectl -n ntfy rollout status deployment/ntfy --timeout=5m
curl --fail --resolve ntfy.unbeholden.dev:443:192.168.4.200 https://ntfy.unbeholden.dev/v1/health
```

## Cut over

1. Add an exact AdGuard rewrite for `ntfy.unbeholden.dev` to `192.168.4.200`.
2. Log in on the phone as `admin` and resubscribe to each topic.
3. Give each publisher an `apps` token from `sops -d`, as
   `Authorization: Bearer tk_...`, or Basic auth with an empty user.
   Proxmox on `rune` posts to `http://192.168.4.12:5123` today; point it at
   `https://ntfy.unbeholden.dev/pve`. That needs a router rule from `rune` to
   `192.168.4.200` tcp/443.
4. On Giran, point the Dokploy route for `ntfy.unbeholden.dev` at
   `https://192.168.4.200`, keeping the Host header, with
   `serverName: ntfy.unbeholden.dev` in its servers transport so the
   certificate check passes. Giran's `.200:443` grant already covers it.
5. Stop ntfy on `aden`. Then drop `aden:5123` from `tag:giran` in
   `playbooks/files/headscale/policy.hujson`, apply it, and remove the router
   rule `rune_ntfy`.

Rate limits key on the user for authenticated requests. Traefik does not trust
forwarded headers, so ntfy sees a cluster address for every client; only the
per-IP login-failure limit is shared.

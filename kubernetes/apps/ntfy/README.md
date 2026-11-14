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

The message cache and user database sit on `talos-worker-01` (see Storage).
Losing them loses only cached messages; Git recreates the accounts.

## Storage

The message cache and user database live on the `storage` claim from the
`local-path` StorageClass (see
[Local Path Provisioner](../../infrastructure/local-path-provisioner/)), on
`talos-worker-01`.

## Deploy and test

```sh
flux reconcile kustomization flux-system --with-source
kubectl -n ntfy wait --for=condition=Ready certificate/ntfy --timeout=20m
kubectl -n ntfy rollout status deployment/ntfy --timeout=5m
curl --fail --resolve ntfy.unbeholden.dev:443:192.168.4.200 https://ntfy.unbeholden.dev/v1/health
```

## Giran route

Giran's Dokploy Traefik routes `ntfy.unbeholden.dev` to `https://192.168.4.200`,
passing the Host header, with `serverName: ntfy.unbeholden.dev` in its servers
transport so the certificate check passes.

## Publishers

Each publisher uses an `apps` token from `sops -d`, as
`Authorization: Bearer tk_...`, or Basic auth with an empty user. Proxmox on
`rune` posts to `https://ntfy.unbeholden.dev/pve`.

Rate limits key on the user for authenticated requests. Unless `behind-proxy`
is set, ntfy keys per-IP limits on the connection, a cluster address for every
client; only the per-IP login-failure limit is then shared.

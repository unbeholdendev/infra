# Certificate management

Installs the official cert-manager chart **v1.21.3** and the community Spaceship
webhook chart/app **0.1.3**. Flux orders reconciliation:

```text
cert-manager → spaceship-webhook → cert-issuers → traefik → apps
```

The first stage installs cert-manager's CRDs, controller, admission webhook and
CA injector. The second adds a DNS-01 solver as an aggregated Kubernetes API.
Its internal serving certificates are issued by cert-manager using a private,
self-signed CA; those do not contact Let's Encrypt or Spaceship.

The issuers stage registers `letsencrypt-staging` and `letsencrypt-production`
with `acme@unbeholden.dev`. Both select only `*.home.unbeholden.dev` and use the
encrypted Spaceship Secret. The staging issuer remains for future tests;
there is no active staging Certificate.

Traefik requests one production wildcard certificate in
`traefik/home-wildcard-tls`, separate from the staging test Secret and ACME
account keys. Its Flux Kustomization waits for the issuers and allows twenty
minutes for issuance. Traefik serves it as the default certificate for every
HTTPS route; cert-manager handles renewals. A failed renewal affects them all.
Apps need no `Certificate` or Ingress TLS section. The wildcard covers one label:
neither `home.unbeholden.dev` nor `a.b.home.unbeholden.dev`.

## Security and DNS

The namespace enforces restricted pod security. The Spaceship chart has no
security-context values, so Helm post-render patches run its pod as UID/GID
65532, drop all capabilities, use a read-only root filesystem and listen on
8443 instead of a privileged port. Its ClusterIP Service still uses port 443.

The chart's Secret-reading Role is narrowed to `get` on
`cert-manager/spaceship-credentials`. The pinned solver source reads both fields
from the challenge's resource namespace; for this ClusterIssuer that is
cert-manager's default cluster-resource namespace, `cert-manager`. No Secret
listing or watching is needed. Its remaining RBAC allows Kubernetes delegated
authentication and cert-manager to call the solver API.

The [SOPS](../../SECRETS.md)-encrypted Secret contains `api-key` and `api-secret`.
It reuses Caddy's Spaceship credential with DNS Records Write permission; do not
revoke or rotate it without updating both consumers until Caddy is retired. The
solver selector is routing configuration, not an API credential security
boundary. The credential can change whatever DNS records its provider
permissions allow.

cert-manager uses public recursive resolvers `1.1.1.1:53` and `9.9.9.9:53` for
DNS-01 self-checks, rather than AdGuard's private wildcard rewrite. It needs
outbound TCP/UDP DNS to those resolvers and HTTPS to ACME; the solver needs
HTTPS to `spaceship.dev`. No inbound Internet connection, public HTTP route or
AdGuard change is needed to prove ownership using a public TXT record.

## Verify after merging

On the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n cert-manager get helmreleases,pods,certificates,issuers
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" get apiservice v1alpha1.cert-manager-webhook-spaceship.hjwylde.github.io
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" get clusterissuers letsencrypt-staging letsencrypt-production
```

Expect both HelmReleases Ready, four running controller/webhook pods, two Ready
internal Certificates and two Ready internal Issuers. A completed startup check
Job pod may also appear. The APIService should report Available and both
ClusterIssuers Ready. Production issuance can take several minutes for DNS
propagation; check the Certificate rather than retrying production requests.

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n traefik wait --for=condition=Ready certificate/home-wildcard --timeout=20m
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n traefik get certificates,orders,challenges
```

Expect `home-wildcard` Ready and its ACME Order valid. The Challenge may already
be gone after completion; if still present, allow cleanup to finish. Confirm
cert-manager's public TXT record at `_acme-challenge.home.unbeholden.dev` is
removed. Caddy uses the same name for its own wildcard until it is retired, so
leave other values alone. If issuance fails, describe `certificate/home-wildcard`
and the relevant Order/Challenge without printing Secrets. A Ready issuer alone
only proves ACME account registration, not certificate issuance.

Follow Traefik's [verification steps](../traefik/) to check the served
certificate. Exact AdGuard rewrites point cluster hostnames to `192.168.4.200`;
keep Caddy, Radicale and the wildcard rewrite unchanged. No public inbound access
is needed for issuance.

Flux prunes the per-app Certificates but cert-manager retains their Secrets. Once
every route serves the wildcard, remove them:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage delete secret homepage-tls --ignore-not-found
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n forgejo delete secret forgejo-tls --ignore-not-found
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n litellm delete secret litellm-tls --ignore-not-found
```

The temporary staging Certificate manifest is removed, stopping its renewals.
cert-manager normally retains the generated TLS Secret. Once Flux has removed
the test Certificate, this command removes only its leftover test Secret:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n cert-manager delete secret dashboard-staging-tls --ignore-not-found
```

Keep the staging issuer and its account key for future tests. Do not delete the
Spaceship credential or the production certificate/account Secrets.

To diagnose failures, describe the failing resource and inspect the relevant
pod logs with the same kubeconfig. Do not print Secrets while debugging.
cert-manager retains CRDs on Helm uninstall by default; do not delete the CRDs
or namespace as routine troubleshooting, since that can destroy certificate
resources or keys.

## References

- [cert-manager Helm installation](https://cert-manager.io/docs/installation/helm/)
- [cert-manager v1.21.3](https://github.com/cert-manager/cert-manager/releases/tag/v1.21.3)
- [ACME configuration](https://cert-manager.io/docs/configuration/acme/)
- [DNS-01 and recursive self-checks](https://cert-manager.io/docs/configuration/acme/dns01/)
- [External DNS-01 webhooks](https://cert-manager.io/docs/configuration/acme/dns01/webhook/)
- [Spaceship webhook v0.1.3 source](https://github.com/hjwylde/cert-manager-webhook-spaceship/tree/v0.1.3)
- [Spaceship webhook chart 0.1.3](https://github.com/hjwylde/cert-manager-webhook-spaceship/releases/tag/cert-manager-webhook-spaceship-0.1.3)

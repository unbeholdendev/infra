# Certificate management

Installs the official cert-manager chart **v1.21.3** and the community Spaceship
webhook chart/app **0.1.3**. Flux orders reconciliation:

```text
cert-manager → spaceship-webhook → cert-issuers
```

The first stage installs cert-manager's CRDs, controller, admission webhook and
CA injector. The second adds a DNS-01 solver as an aggregated Kubernetes API.
Its internal serving certificates are issued by cert-manager using a private,
self-signed CA; those do not contact Let's Encrypt or Spaceship.

The final stage registers `letsencrypt-staging` with `acme@unbeholden.dev`.
It selects only `dashboard.home.unbeholden.dev`. An encrypted Spaceship Secret
and temporary `dashboard-staging` Certificate now test the full DNS-01 flow.
The certificate is stored as `cert-manager/dashboard-staging-tls`, not connected
to Traefik. No production issuer, Traefik TLS change or DNS rewrite is included.

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
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" get clusterissuer letsencrypt-staging
```

Expect both HelmReleases Ready, four running controller/webhook pods, two Ready
internal Certificates and two Ready internal Issuers. A completed startup check
Job pod may also appear. The APIService should report Available and the staging
ClusterIssuer Ready. The temporary dashboard certificate may take a few minutes
to issue; `cert-issuers` waits up to ten minutes for readiness.

Check the actual DNS-01 test:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n cert-manager wait --for=condition=Ready certificate/dashboard-staging --timeout=10m
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n cert-manager get certificate dashboard-staging
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n cert-manager get orders,challenges
```

Expect the Certificate Ready and its ACME Order valid. The Challenge may already
be gone after completion; if still present, it should be valid and no longer
presented. Confirm Spaceship has removed the temporary TXT record at
`_acme-challenge.dashboard.home.unbeholden.dev`. Leave unrelated records alone.
If issuance fails, describe `certificate/dashboard-staging` and the relevant
Order/Challenge without printing Secrets. DNS API access has real effects even
though the certificate uses staging.

Staging certificates are not browser-trusted. Request production TLS and change
the exact AdGuard rewrite only after this test succeeds; preserve Caddy,
Radicale and the wildcard rewrite. Remove the temporary Certificate manifest
after the test to stop its renewals; keep the staging issuer for future tests.
cert-manager normally retains the generated TLS Secret when a Certificate is
removed, so delete only `cert-manager/dashboard-staging-tls` after that manifest
removal has reconciled.

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

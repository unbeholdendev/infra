# Traefik HTTPS routing

Traefik chart 42.1.3 runs one non-root proxy pod in a restricted namespace.
MetalLB assigns `192.168.4.200` to its LoadBalancer Service, exposing TCP 80 and
443. HTTP redirects permanently to HTTPS for all routes on this proxy. No host
networking, host ports, allocated NodePorts, persistent volume or Traefik ACME
resolver is configured. The management dashboard is disabled and the API is
not exposed.

The standard Kubernetes Ingress API selects the `traefik` class and `websecure`
entrypoint. Its TLS section references `homepage/homepage-tls`, issued and
renewed by [cert-manager](../cert-manager/). Traefik terminates TLS and forwards
HTTP to Homepage's private ClusterIP Service. No Traefik routing CRDs or Gateway
API are used; the unused CRD provider and chart CRD installation remain disabled.

Flux waits for `metallb-config` before installing Traefik. Homepage waits for
Traefik and the certificate issuers. Its existing pod and port-forward access
remain available while dependencies become ready. A proxy rollout or the
separate Helm/Ingress reconciliations may briefly interrupt routing.

## Verify after merge

Flux detects the merge automatically. On the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n traefik get helmrelease,pods,service
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage get ingress,certificate
curl --noproxy '*' --fail --show-error --connect-timeout 5 --max-time 15 --resolve dashboard.home.unbeholden.dev:443:192.168.4.200 -I https://dashboard.home.unbeholden.dev/
curl --noproxy '*' --show-error --connect-timeout 5 --max-time 15 --resolve dashboard.home.unbeholden.dev:80:192.168.4.200 -I http://dashboard.home.unbeholden.dev/
```

Expect the release/pod and certificate Ready, the Service EXTERNAL-IP
`192.168.4.200` with ports 80 and 443, HTTPS returning 200 with successful
certificate validation, and HTTP returning a permanent redirect to
`https://dashboard.home.unbeholden.dev/`. Do not use `-k`: the trusted certificate
is part of the test. The Service EXTERNAL-IP means an address outside the
cluster network, not a public internet address.

`--resolve` bypasses DNS while preserving the HTTP Host and TLS server name.
Then test normal DNS access, from both LAN and Tailscale:

```sh
curl --noproxy '*' --fail --show-error --connect-timeout 5 --max-time 15 -I https://dashboard.home.unbeholden.dev/
```

Open <https://dashboard.home.unbeholden.dev> in a browser. The exact AdGuard
rewrite already points to `.200`; leave the wildcard rewrite, Caddy and
Radicale unchanged. HTTPS is encryption, not application authentication: keep
the service private through LAN/Tailscale routing and firewall policy. No WAN
forwarding is needed or created. Sensitive widgets or authentication need a
separate review.

If the address is assigned but connections time out, check the routed/firewall
path for TCP 443. An HTTP 404 suggests an Ingress hostname/entrypoint mismatch.
A default/self-signed certificate suggests the TLS Secret is missing or not
loaded, or the request used the wrong server name; do not bypass validation.
If HTTP redirects but HTTPS fails, use the checks above before changing DNS.

## References

- [Chart 42.1.3 values](https://github.com/traefik/traefik-helm-chart/blob/v42.1.3/traefik/values.yaml)
- [Kubernetes Ingress routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [Entrypoint redirection](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/#redirection)
- [Ingress provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress/)
- [MetalLB address selection](https://metallb.io/usage/)

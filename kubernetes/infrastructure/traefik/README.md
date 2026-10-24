# Traefik HTTP routing

Traefik chart 42.1.3 runs one ordinary non-root proxy pod in a restricted
namespace. The control-plane taint leaves it on the worker. MetalLB assigns
`192.168.4.200` to its LoadBalancer Service, which exposes only TCP 80. No host
networking, host ports, allocated NodePorts, persistent volume or certificate
resolver is configured. The management dashboard is disabled and the API is
not exposed.

This uses the standard Kubernetes Ingress API, not Traefik-specific routing
CRDs or Gateway API. The unused CRD provider and chart CRD installation are
both disabled. The IngressClass is explicitly selected, not made the cluster
default. HTTPS will be added separately with cert-manager.

Flux waits for `metallb-config` before installing Traefik. Homepage then waits
for Traefik before applying its hostname-based route. Existing Homepage pods
and port-forward access remain available while dependencies become ready.

## Verify after merge

Flux detects the merge automatically; manual reconciliation is optional.
On the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n traefik get helmrelease,pods,service
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage get ingress
curl --noproxy '*' --fail --show-error --connect-timeout 5 --max-time 15 --resolve dashboard.home.unbeholden.dev:80:192.168.4.200 -I http://dashboard.home.unbeholden.dev/
```

Expect the release and pod to become Ready, the Service to show EXTERNAL-IP
`192.168.4.200` with only port 80, and the request to return HTTP 200. The
Service's EXTERNAL-IP column means an address outside the cluster network;
it does not mean a public internet address.

`--resolve` bypasses DNS for this request while sending the correct Host header.
It tests the MetalLB address, routing and application without changing AdGuard.
Repeat from LAN and Tailscale paths. Direct IP requests need not reach Homepage:
its route matches `dashboard.home.unbeholden.dev`, not every hostname.

Leave AdGuard's wildcard rewrite, Caddy and Radicale unchanged. Do not add the
exact dashboard rewrite until reachability is verified. This is HTTP only,
without application authentication: do not add credentials or sensitive widgets
yet. Browsers may upgrade HTTP because of cached HSTS; use curl for this stage.
Keep the service private through the existing LAN/Tailscale routing and firewall
policy; no WAN forwarding is needed or created.

If the IP remains pending, inspect the Service events and MetalLB logs. If the
address is assigned but connections time out, check ARP, Proxmox IP filtering,
and the routed/firewall path. An HTTP 404 indicates the proxy may be reachable
but the requested hostname/route needs checking.

## References

- [Chart 42.1.3 values](https://github.com/traefik/traefik-helm-chart/blob/v42.1.3/traefik/values.yaml)
- [Kubernetes Ingress routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [Ingress provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress/)
- [MetalLB address selection](https://metallb.io/usage/)

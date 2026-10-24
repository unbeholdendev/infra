# MetalLB

MetalLB supplies private addresses for Kubernetes LoadBalancer Services. This
stage installs chart 0.16.1 in native mode, with no FRR/BGP components, and
reserves `192.168.4.200` for the future ingress proxy. No proxy, DNS rewrite,
certificate configuration or public port forwarding is added here.

Flux installs the controller, speakers, CRDs and webhook first. The separate
`metallb-config` Kustomization depends on that installation becoming healthy
before applying the address pool and Layer 2 advertisement.

## Prerequisites

- Keep `192.168.4.200` outside DHCP and all other static assignments. It is a
  service address, not another VM or a secondary address to add in Talos.
- The VLAN 4 bridge/switch path must pass ARP and traffic for the service IP.
  Proxmox IP filtering, if configured, must allow the service IP on any announcing
  VM. Do not disable firewalling globally to troubleshoot this.
- Speakers need TCP/UDP 7946 between nodes. The Kubernetes API must reach the
  MetalLB admission webhook on TCP 9443. Existing packet filters must permit
  these paths; this configuration does not change router or Proxmox rules.
- If kube-proxy uses IPVS mode, enable `strictARP` through Talos configuration
  before using MetalLB. This is not required for iptables mode. Check the running
  kube-proxy configuration rather than applying kubeadm-specific instructions.

The official chart's speaker uses host networking and elevated network
permissions. Only `metallb-system` gets the required privileged Pod Security
Admission labels; Homepage keeps its restricted policy. The chart normally runs
speakers on both nodes, but respects the control plane's
`node.kubernetes.io/exclude-from-external-load-balancers` label when advertising.
The controller is an ordinary workload and should schedule on the worker.

## Verify after merge

Flux discovers the merge automatically. Manual reconciliation only skips the
polling wait. On the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n metallb-system get helmrelease,pods
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n metallb-system get ipaddresspool,l2advertisement
```

Expect both Flux Kustomizations and the HelmRelease to become Ready, the
controller and speakers to run, and the `ingress` pool to contain exactly
`192.168.4.200/32`.

The pool has `autoAssign: false`: a future proxy LoadBalancer Service must
explicitly select it with `metallb.io/address-pool: ingress`. This prevents an
unrelated Service consuming the only reserved IP. No existing Service changes
type in this stage, so the address is not allocated or advertised yet. A ping or
browser request to `.200` is not an installation test; end-to-end reachability
will be checked when Traefik is added.

Leave the AdGuard wildcard rewrite and Caddy unchanged. A later stage will add
an exact `dashboard.home.unbeholden.dev` rewrite after the proxy is reachable.

## References

- [Installation and permissions](https://metallb.io/installation/)
- [Layer 2 configuration](https://metallb.io/configuration/)
- [Address allocation](https://metallb.io/configuration/_advanced_ipaddresspool_configuration/)
- [Chart 0.16.1 values](https://github.com/metallb/metallb/blob/metallb-chart-0.16.1/charts/metallb/values.yaml)

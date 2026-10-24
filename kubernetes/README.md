# Homelab Kubernetes

Flux watches `clusters/homelab` on `main`. Its root Kustomization includes Flux
itself and reconciliation objects for workloads and infrastructure. Homepage's
resources live in `apps/homepage` and reconcile separately, with readiness checks.

## MetalLB

[`infrastructure/metallb`](infrastructure/metallb/) installs MetalLB and reserves
`192.168.4.200` for a future proxy LoadBalancer Service. The controllers must be
ready before Flux applies the pool configuration. This does not expose Homepage
or change DNS; see that directory's README for prerequisites and verification.

## Homepage

Homepage v2.7.0 runs as one non-root pod with no Kubernetes API token, discovery
permissions, secrets or persistent storage. The only Service is ClusterIP:
there is no ingress, NodePort, LoadBalancer, host port or DNS change yet.
The pod should schedule on the worker while the control-plane taint remains.

Edit `apps/homepage/config/services.yaml` for links and `settings.yaml` for page
settings. Kustomize generates a versioned ConfigMap; config changes update the
Deployment's volume reference and roll the pod. All expected config files are
provided, mounted read-only, and logs go to stdout instead of a writable config
volume. No container socket or Kubernetes discovery integration is enabled.

After merging, run these on the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux reconcile kustomization flux-system --with-source --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage get pods -o wide
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage port-forward service/homepage 3000:3000
```

Leave the last command running and open <http://localhost:3000>. Port forwarding
binds to localhost by default; do not add `--address 0.0.0.0`. Stop it with Ctrl+C.
If the Deployment is still starting, wait for its pod to become Ready first.

`HOMEPAGE_ALLOWED_HOSTS` includes the pod IP for probes and the planned
`dashboard.home.unbeholden.dev` hostname. Homepage also allows `localhost:3000`
and `127.0.0.1:3000` by default. This check is not authentication. TLS, proxying,
and LAN/Tailscale access at the final hostname are separate work; Caddy and
Radicale remain unchanged. The starter page contains links only, with no widget
credentials or application authentication.

For failures, inspect `kubectl -n homepage describe pod` and `kubectl -n homepage
logs deployment/homepage`, using the same kubeconfig. A Flux Kustomization may
remain unhealthy until the Deployment is ready.

## References

Checked against the current official documentation and v2.7.0 source:

- [Kubernetes installation](https://gethomepage.dev/installation/k8s/)
- [Allowed hosts and authentication](https://gethomepage.dev/installation/)
- [Homepage v2.7.0](https://github.com/gethomepage/homepage/releases/tag/v2.7.0)
- [Console-only logging](https://github.com/gethomepage/homepage/blob/v2.7.0/src/utils/logger.js)
- [Flux Kustomizations](https://fluxcd.io/flux/components/kustomize/kustomizations/)

The upstream Kubernetes example includes discovery RBAC, a ServiceAccount token,
and an Ingress. Those are omitted because this deployment only serves static
links over port-forwarding. Its mutable `latest` image tag is replaced with a
release pin.

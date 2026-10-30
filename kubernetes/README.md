# Homelab Kubernetes

Flux watches `clusters/homelab` on `main`. Its root Kustomization includes Flux
itself and reconciliation objects for workloads and infrastructure. Homepage's
resources live in `apps/homepage` and reconcile separately, with readiness checks.

For daily checks, logs, container shells and terms, see the
[Talos + Kubernetes cheat sheet](CHEATSHEET.md).

## Secrets

[SOPS with age](SECRETS.md) keeps Secret values encrypted in Git. Create the
private decryption Secret on the laptop before merging the Flux configuration.
The public recipient is tracked; the private identity is backed up in
Vaultwarden, without giving the cluster access to Vaultwarden.

## MetalLB

[`infrastructure/metallb`](infrastructure/metallb/) installs MetalLB and reserves
`192.168.4.200` for the proxy LoadBalancer Service. The controllers must be
ready before Flux applies the pool configuration. See that directory's README
for prerequisites and verification.

## Traefik

[`infrastructure/traefik`](infrastructure/traefik/) serves
`https://dashboard.home.unbeholden.dev` on `192.168.4.200:443` and redirects
HTTP to HTTPS. See its README for TLS tests from LAN and Tailscale. AdGuard's
exact dashboard rewrite points to `.200`; Caddy and the wildcard stay unchanged.

## Certificates

[`infrastructure/cert-manager`](infrastructure/cert-manager/) installs
cert-manager, the community Spaceship DNS-01 webhook and Let's Encrypt staging
and production issuers. Traefik requests one `*.home.unbeholden.dev` certificate
using the encrypted Spaceship credentials and serves it for every HTTPS route.
See its README for verification and cleanup.

## Homepage

Homepage v2.7.0 runs as one non-root pod with no Kubernetes API token, discovery
permissions, mounted secrets or persistent storage. Its Service stays ClusterIP;
a Traefik Ingress provides hostname-based HTTPS access through the proxy.
The pod should schedule on the worker while the control-plane taint remains.

Edit `apps/homepage/config/services.yaml` for links and `settings.yaml` for page
settings. Kustomize generates a versioned ConfigMap; config changes update the
Deployment's volume reference and roll the pod. All expected config files are
provided, mounted read-only, and logs go to stdout instead of a writable config
volume. No container socket or Kubernetes discovery integration is enabled.

Flux deploys merges automatically. For status and optional local access, run
these on the laptop:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage get pods -o wide
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n homepage port-forward service/homepage 3000:3000
```

Leave the last command running and open <http://localhost:3000>. Port forwarding
binds to localhost by default; do not add `--address 0.0.0.0`. Stop it with Ctrl+C.
If the Deployment is still starting, wait for its pod to become Ready first.

`HOMEPAGE_ALLOWED_HOSTS` includes the pod IP for probes and the planned
`dashboard.home.unbeholden.dev` hostname. Homepage also allows `localhost:3000`
and `127.0.0.1:3000` by default. This check is not authentication. HTTPS encrypts
traffic but does not authenticate users; Caddy and Radicale remain unchanged.
The starter page contains links only, with no widget credentials or application
authentication.

For failures, inspect `kubectl -n homepage describe pod` and `kubectl -n homepage
logs deployment/homepage`, using the same kubeconfig. A Flux Kustomization may
remain unhealthy until the Deployment is ready.

## Forgejo

[`apps/forgejo`](apps/forgejo/) prepares the private Forgejo migration with a
retained worker-local volume, HTTPS and SSH. The Deployment stays stopped until
the source is stopped and its complete data directory restored. Its README
covers preparation, manual restore, validation, cutover and recovery. This stage
does not change DNS, Flux's Git source or the old public instance.

## LiteLLM

[`apps/litellm`](apps/litellm/) trials Claude Code subscription forwarding at
`llm.home.unbeholden.dev`, with client virtual keys, PostgreSQL and 14-day request
logs. Pi's native OpenAI subscription stays direct pending compatibility tests.
Apply the manual Talos volume patch before startup. Storage is worker-local and
has no backups for this trial; its README covers deployment, acceptance checks
and client rollback.

## Renovate

[`apps/renovate`](apps/renovate/) runs daily and opens dependency update PRs on
selected `unbeholden` repositories. Its README covers selection, credentials and
manual runs.

## References

Checked against the current official documentation and v2.7.0 source:

- [Kubernetes installation](https://gethomepage.dev/installation/k8s/)
- [Allowed hosts and authentication](https://gethomepage.dev/installation/)
- [Homepage v2.7.0](https://github.com/gethomepage/homepage/releases/tag/v2.7.0)
- [Console-only logging](https://github.com/gethomepage/homepage/blob/v2.7.0/src/utils/logger.js)
- [Flux Kustomizations](https://fluxcd.io/flux/components/kustomize/kustomizations/)

The upstream Kubernetes example includes discovery RBAC, a ServiceAccount token,
and an Ingress. Discovery permissions are omitted because this deployment only
serves static links. The Ingress explicitly selects Traefik, and the mutable
`latest` image tag is replaced with a release pin.

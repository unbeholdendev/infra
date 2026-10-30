# Talos + Kubernetes cheat sheet

Run on the laptop. Talos manages the node OS (`talosctl`), Kubernetes runs
workloads (`kubectl`), and Flux makes the cluster match Git (`flux`).

## Connect

```sh
export KUBECONFIG="$HOME/talos/dion/kubeconfig"
export TALOSCONFIG="$HOME/talos/dion/talosconfig"
kubectl config current-context
talosctl config info
```

Keep both config files private. If Flux is missing, run `nix shell nixpkgs#fluxcd`.

## Check and watch

```sh
kubectl get nodes -o wide
kubectl get pods -A -o wide
flux get all -A
kubectl get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp
```

Expect nodes `Ready`, running pods with all containers ready (`1/1`, `2/2`),
and Flux `Ready=True`. Completed Jobs are normal; rising restart counts need a
look. `Running` alone does not mean ready. Events expire and may describe an
already resolved problem.

`-A` means all namespaces; `-n homepage` selects one. Run watches in separate
terminals; Ctrl+C stops watching, not the workload:

```sh
kubectl get pods -A -w
flux get kustomizations -A --watch
```

## Follow a deployment

Flux watches **main**, not your local files or feature branch:

```text
merge → Git source fetches commit → Flux applies manifests → pods become ready
```

```sh
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
kubectl -n homepage rollout status deployment/homepage --timeout=5m
```

Check the Flux revision first: rollout status can report success for the old
Deployment. A dependency failure means inspect that dependency before the app.

To trigger a fresh reconcile (these can apply changes):

```sh
flux reconcile kustomization flux-system -n flux-system --with-source
flux reconcile kustomization homepage -n flux-system --with-source
```

## Find the failure

```sh
kubectl -n homepage get pods
```

Set `POD` to a current pod name from that output:

```sh
POD=REPLACE_WITH_POD_NAME
kubectl -n homepage describe pod "$POD"
kubectl -n homepage logs "$POD" -c homepage --tail=100 --timestamps
kubectl -n homepage logs "$POD" -c homepage --previous --tail=100
```

`describe` shows state, probes, scheduling and events. `--previous` reads the
previous container instance after a restart; add `-f` to normal logs to follow.
Collect evidence before deleting or restarting anything.

| Symptom | First check |
| --- | --- |
| `Pending` | Scheduling events: resources, taints, volumes |
| `ImagePullBackOff` | Image name/tag, registry access and credentials |
| `CrashLoopBackOff` | Current and previous logs |
| `OOMKilled` | Memory use and limits |
| `Running`, `0/1` ready | Readiness probe and app logs |
| Node `NotReady` | Node description, Talos services and kubelet logs |
| Flux `Ready=False` | `kubectl -n flux-system describe kustomization NAME` |

## Enter a container or reach the app

```sh
kubectl -n homepage exec -it "$POD" -c homepage -- /bin/sh
```

`-c` selects the container; `--` separates kubectl options from its command.
Leave with `exit`. Minimal images may have no shell or debugging tools.
Container edits are not durable; Homepage's config is read-only.

```sh
kubectl -n homepage port-forward service/homepage 3000:3000
```

Open <http://localhost:3000>; keep the terminal running. Leave the default
localhost binding. Ctrl+C closes the tunnel.

Normal access follows this path:

```text
DNS → 192.168.4.200 (MetalLB) → Traefik → Ingress rule → Service → ready pod
```

```sh
kubectl -n traefik get service,pods
kubectl -n homepage get ingress,service,endpointslices
```

Port-forward works but the hostname fails? Check DNS, routing/firewall, Traefik
and TLS. HTTPS is not user authentication; keep access private on LAN/Tailscale.

## Inspect Talos

Find Internal IPs with `kubectl get nodes -o wide`, then choose one:

```sh
NODE_IP=REPLACE_WITH_NODE_IP
talosctl -n "$NODE_IP" services
talosctl -n "$NODE_IP" logs kubelet
talosctl -n "$NODE_IP" dmesg
talosctl -n "$NODE_IP" dashboard
```

Talos has no normal SSH shell. Your talosconfig also needs a reachable Talos API
endpoint; `-n` selects the target node. Do not bootstrap or reset as routine
troubleshooting. One control plane and one worker are not highly available;
monitor the Proxmox host and its storage too.

## Terms

| Term | Meaning |
| --- | --- |
| Node / namespace | A machine / a scope grouping resources |
| Pod / container | Kubernetes' scheduled unit / a process environment inside it |
| Deployment → ReplicaSet → Pod | Declares rollout → maintains replica count → runs containers |
| Service / Ingress | Stable access to pods / HTTP routing rules implemented by Traefik |
| Label / selector | A tag / a query selecting tagged resources |
| ConfigMap / Secret | Non-secret config / sensitive data; base64 is not encryption |
| PVC | Request for persistent storage |
| Readiness / liveness probe | Ready for traffic / needs a restart |
| Request / limit | Scheduling resource amount / enforced resource cap |
| Reconciliation | Repeatedly making actual state match desired state |
| Flux Kustomization / HelmRelease | Manifests Flux applies / chart installation Flux manages |
| CRD / RBAC | A custom API resource definition / API permission rules |

`kubectl explain deployment.spec` explains fields. `kubectl get all` does **not**
list every resource type. Make lasting changes and rollbacks in Git; Flux may
undo live edits. Back up credentials, etcd and application data outside the
cluster—Git alone is not a backup.

## Useful tools, in order

- **[K9s](https://k9scli.io/):** terminal UI for status, logs and resource browsing.
  Try `nix shell nixpkgs#k9s --command k9s --readonly`; `?` shows help.
- **[Headlamp](https://headlamp.dev/):** graphical alternative. Try the desktop
  app with your kubeconfig before hosting another privileged web UI.
- **[Stern](https://github.com/stern/stern):** follow logs across changing pods:
  `stern -n homepage homepage --since 10m`.
- **Metrics Server:** enables `kubectl top nodes` and `kubectl top pods -A`.
  No history; configure kubelet certificate trust rather than disabling TLS checks.
- **External uptime checks:** run outside this cluster so a cluster outage can
  still notify you.
- **Prometheus + Grafana + Alertmanager:** historical metrics, dashboards and
  alerts. Budget RAM/storage and test alert delivery before relying on it.
  Add Loki with a supported collector later if you need logs retained after pods
  disappear.

# Private Forgejo

Forgejo 16.0.6 runs at `git.home.unbeholden.dev` for LAN/Tailscale access, with
one replica and Flux fetching from the private instance. DNS, client credential
helpers, the live Flux Git Secret and public proxy routes need separate updates.
The restore procedure below requires a temporary zero-replica post-render patch;
do not run a replacement instance alongside the source.

Flux installs the maintained Forgejo chart through an OCIRepository and
HelmRelease in `release.yaml`. Chart 17.3.2 is pinned separately from the
application image, which stays at 16.0.6 to avoid a database upgrade during
migration. The chart owns the Deployment, Services and Ingress; Kustomize owns
the namespace and `storage` claim. The restore pod stays manual.

HTTPS uses Traefik at `192.168.4.200`. A separate LoadBalancer Service shares
that private IP for SSH on port `222`, forwarding to the container's port `22`.
Both Services use MetalLB's `private-ingress` sharing key and `Cluster` traffic
policy. No new IP, NodePort, WAN forward or Traefik TCP provider is needed.
Keep the router's WAN forwards and public gateway routes away from `.200`.

Giran retains tailnet access to `.200:443` and `.200:222` through Headscale's
`tag:giran` grant. Applications on Giran must use `git.home.unbeholden.dev` so
HTTPS certificate validation and Traefik routing work. The hostname must resolve
to `.200`, reached through the tailnet subnet route. The IP-based HTTPS grant
covers the shared Traefik listener, not only Forgejo. Do not proxy it publicly.

## Storage and process

Forgejo's `/data` is the `storage` claim from the `local-path` StorageClass (see
[Local Path Provisioner](../../infrastructure/local-path-provisioner/)). It binds
to the node that first runs a pod using it, `talos-worker-01`, and lives on the
worker's EPHEMERAL filesystem, shared with images and logs. It survives pod
restarts and node reboots, not a disk wipe, reprovision or loss of the worker.

The claim's 10 GiB is not a reservation or quota: watch actual worker free space
and leave room for images and logs. The namespace and claim opt out of Flux
pruning, and the StorageClass retains data when a claim is deleted. Removing the
application does not clean up its stored files. Never wipe the worker or delete
these resources as a way to restart Forgejo.

The standard image preserves the source's `/data` layout and OpenSSH host keys.
Its entrypoint starts as root to set permissions and launch SSH, then runs
Forgejo as UID/GID 1000. This requires a baseline namespace, rather than
Homepage's restricted policy. There is no service-account token, host networking
or privileged application container. `Recreate` avoids overlapping old and new
pods during a rollout. Do not scale above one replica with SQLite.

The chart's `initPreScript` refuses startup without an explicit restore-complete
marker, restored configuration, SQLite file at `/data/gitea/gitea.db`, repository
directory and explicit `DB_TYPE = sqlite3`. It runs before the chart scripts
change configuration or invoke database migration. If the source uses different
paths, ownership, database or image version, stop and adjust the chart values
before restoring. Do not create an empty database to get past the check.

The values explicitly preserve the database, repository and application-data
paths; chart defaults would otherwise move them. The chart merges its settings
into the restored `app.ini` and preserves existing security and JWT secrets.
Automatic admin creation is disabled, so restored accounts remain authoritative.
No database or cache service is deployed. The chart also manages local cache,
queue and session defaults; review the rendered inline configuration against any
source customisations before startup. Do not put source secrets in chart values.

The chart rejects `replicaCount: 0`; its values request one replica. For a fresh
restore, temporarily add this entry under the HelmRelease's
`spec.postRenderers[0].kustomize.patches` before reconciliation:

```yaml
- target:
    group: apps
    version: v1
    kind: Deployment
    name: forgejo
  patch: |
    - op: replace
      path: /spec/replicas
      value: 0
```

Remove it to activate Forgejo after restore. This keeps chart schema validation
enabled. The existing Service post-render patch disables SSH NodePort allocation,
which the chart does not expose as a value; keep that patch.

## Prepare a fresh restore

Run from this repository on the laptop, with the working homelab `KUBECONFIG`
and the temporary zero-replica patch in place:

```sh
flux get kustomizations
kubectl -n forgejo get helmrelease,ocirepository,deployment,pvc,service
kubectl -n traefik get service
```

Expect the Deployment at zero replicas and both LoadBalancer Services assigned
`.200`. The `storage` claim stays Pending until a pod uses it. Forgejo HTTPS can
return 503 while it is stopped. Check that Homepage still serves normally. Do
not change DNS yet.

The manual restore pod is excluded from Kustomize. It mounts the `storage` claim
in a temporary root container on `talos-worker-01`, which binds a new claim
there. It receives no API token. Forgejo must stay at zero replicas while it
runs.

```sh
kubectl apply -f kubernetes/apps/forgejo/restore-pod.yaml
kubectl -n forgejo wait --for=condition=Ready pod/forgejo-restore --timeout=5m
kubectl -n forgejo exec forgejo-restore -- df -h /data
```

## Back up and restore

Before the final backup, stop source writes, runners and Forgejo on `aden`.
Keep it stopped until the private instance is accepted or rolled back. Merely
copying a running SQLite database is not a consistent backup. Check that the
source really uses SQLite, the expected paths and Forgejo 16.0.6; check for
external package/LFS/attachment storage or additional mounts too.

You own source access. Archive the complete contents of the existing `/data`
mount, including dotfiles, config, database, repository data, packages and SSH
keys. For example, on the source host, replacing the path:

```sh
umask 077
sudo tar -C /path/to/forgejo/data -czpf forgejo-data.tar.gz .
sudo chmod 600 forgejo-data.tar.gz
```

Copy the archive securely to the laptop, outside this checkout. It contains
secrets. Keep an independent copy outside the worker. A `forgejo dump` archive
has a different layout and cannot be extracted using the commands below.

On the laptop, inspect the archive paths and confirm they include
`./gitea/conf/app.ini`, `./gitea/gitea.db` and `./git/repositories`. The archive
must contain data-directory contents, not an enclosing `data/` directory:

```sh
tar -tzf /secure/path/forgejo-data.tar.gz | head -40
kubectl -n forgejo exec forgejo-restore -- sh -ec 'test -z "$(ls -A /data)"'
kubectl -n forgejo exec -i forgejo-restore -- tar -xzpf - -C /data < /secure/path/forgejo-data.tar.gz
kubectl -n forgejo exec forgejo-restore -- sh -ec 'test -s /data/gitea/conf/app.ini; test -s /data/gitea/gitea.db; test -d /data/git/repositories; du -sh /data'
```

Do not continue if the empty-directory check fails. Inspect existing contents
rather than overwriting them or extracting a second backup over the first.
Review the restored database type/path locally without printing the rest of
`app.ini`. Preserve the SQLite WAL/SHM companions if present and the source's
numeric ownership. Confirm the application data is accessible to UID/GID 1000.

On the laptop, check SQLite integrity on a disposable copy extracted from the
archive, including any WAL/SHM companions. This needs free laptop disk space;
keep the original archive unchanged:

```sh
umask 077
check_dir=$(mktemp -d)
tar -xzf /secure/path/forgejo-data.tar.gz -C "$check_dir" --wildcards './gitea/gitea.db*'
nix shell nixpkgs#sqlite --command sqlite3 "$check_dir/gitea/gitea.db" 'PRAGMA integrity_check;'
```

Continue only if the result is `ok` and the restored configuration points to
that database. Remove the disposable directory when finished. After successful
extraction, integrity and configuration checks, explicitly authorise startup:

```sh
kubectl -n forgejo exec forgejo-restore -- touch /data/.forgejo-restore-complete
```

Do not create that marker after a failed or partial extraction. Delete the
helper before starting the application:

```sh
kubectl -n forgejo delete pod forgejo-restore --wait=true
```

## Start and verify

Keep the source stopped. Helm drift detection will revert a live Deployment
scale. Suspend the root Kustomization first so it cannot undo the application's
suspension, then suspend the Forgejo Kustomization. Other existing workloads and
Flux controllers keep running. Leave the HelmRelease running:

```sh
flux suspend kustomization flux-system
flux suspend kustomization forgejo
kubectl -n forgejo edit helmrelease forgejo
```

In the editor, remove only the Deployment replica-zero post-render patch under
`spec.postRenderers`. Keep the Service NodePort patch and `replicaCount: 1`.
The Helm controller will activate Forgejo without fighting a manual scale.
Persist the same patch removal in Git during cutover.

```sh
flux reconcile helmrelease forgejo -n forgejo
kubectl -n forgejo rollout status deployment/forgejo --timeout=10m
kubectl -n forgejo logs deployment/forgejo -c forgejo --tail=100
curl --noproxy '*' --fail --show-error --resolve git.home.unbeholden.dev:443:192.168.4.200 https://git.home.unbeholden.dev/api/healthz
```

Do not bypass TLS verification. Use a temporary laptop hosts entry pointing
`git.home.unbeholden.dev` to `.200` to test the UI and Git before changing shared
DNS. Log in with the existing account; verify repository history, issues,
attachments, packages and Actions settings. Clone and push a disposable test
repository over HTTPS and SSH. Compare the SSH host-key fingerprint against
the source's trusted key; do not blindly replace `known_hosts`.

The restored instance can send mail, run scheduled tasks and deliver webhooks.
Never start it alongside a live source. For an isolated rehearsal instead of
this stopped-source cutover, first disable outgoing integrations and block its
outbound traffic through an enforced firewall policy.

## Cut over

Once validation passes:

1. Change AdGuard's exact `git.home.unbeholden.dev` rewrite to `.200`. Preserve
   the wildcard, Caddy and unrelated services. Test DNS, trusted HTTPS and SSH
   from LAN, Tailscale, runners and inside the cluster.
2. Remove the Deployment replica-zero post-render patch from `release.yaml` in
   Git and update Flux's source URL to
   `ssh://git@git.home.unbeholden.dev:222/unbeholden/infra.git`. Ensure that commit
   is on `main` in the restored instance before switching the live source.
   Update the `flux-system/flux-system` Git Secret's host trust without printing
   its private key. Verify the existing deploy key still authorises access.
   Apply the new GitRepository URL from the laptop and verify Flux fetches the
   intended revision before resuming the Forgejo Kustomization.
3. Update `group_vars/forgejo_clients.yml`, apply the host-scoped credential
   helper on `oren`, and update remotes, runner instance URLs, webhooks and
   OAuth callbacks. Verify authenticated Git operations and a runner job.
   The netcup snapshot workflow needs its existing secret, variable and runner;
   it does not back up Forgejo's new storage.
4. Remove the old public Forgejo HTTPS and SSH proxy routes. Apply the Headscale
   policy, which replaces `tag:giran`'s `aden:3000` and `aden:222` grants with
   `.200:443` and `.200:222`. On Giran, verify the private hostname resolves to
   `.200` and HTTPS/API and SSH access work over the tailnet. Separately verify
   public HTTPS, SSH and registry access no longer reaches Forgejo. Preserve all
   unrelated proxy routes and grants.
5. After the GitRepository has fetched the activation commit from the private
   instance, run `flux resume kustomization flux-system`, then
   `flux resume kustomization forgejo`. Verify both apply that revision, remain
   Ready and keep fetching. Remove temporary laptop hosts entries and obsolete
   Git credentials/trust.

The hostname change also moves the container registry. Update image references
and registry credentials in deployments and build jobs; existing images are
restored, but references to the old hostname do not redirect automatically.

Do not delete the old backup or VM data during cutover. Before the new instance
accepts writes, rollback means scaling it to zero, restoring DNS/client settings
and restarting the unchanged source. After it accepts writes, take a fresh
consistent backup and migrate those changes back before restarting the old
instance. Never enable both writable copies.

## Recovery and ongoing backups

Keep a copy of this repository and the deployment instructions outside Forgejo,
alongside the SOPS identity recovery described in `kubernetes/SECRETS.md`.
Recovering the Git server must not depend on fetching these manifests from it.

The migration archive is not an ongoing backup policy. Before relying on this
instance, arrange regular consistent backups of the full data directory to
storage outside this worker and test a restore. Stop Forgejo for a filesystem
backup or use a documented application-consistent method. Store encryption keys
and configuration with the backup. Monitor free disk space on the shared worker
filesystem. `Retain`, Proxmox storage and a surviving PVC are not backups.

## References

- [Forgejo Helm chart](https://code.forgejo.org/forgejo-helm/forgejo-helm)
- [Forgejo 16 Docker images and configuration](https://forgejo.org/docs/v16.0/admin/installation/docker/)
- [Forgejo backup and restore](https://forgejo.org/docs/latest/admin/setup/backup/)
- [Talos disk layout](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/storage-and-disk-management/disk-management/layout)
- [Talos local storage](https://docs.siderolabs.com/kubernetes-guides/csi/local-storage)
- [MetalLB IP sharing](https://metallb.io/usage/#ip-address-sharing)

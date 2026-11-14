# Private Forgejo

Forgejo runs at `git.home.unbeholden.dev` for LAN/Tailscale access, with one
replica, and Flux fetches this repository from it. A restore needs a temporary
zero-replica post-render patch; never run two instances on the same data.

Flux installs the maintained Forgejo chart through an OCIRepository and
HelmRelease in `release.yaml`. The chart and the application image are
pinned separately. The chart owns the Deployment, Services and Ingress; Kustomize owns
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

The standard image keeps the usual `/data` layout and OpenSSH host keys.
Its entrypoint starts as root to set permissions and launch SSH, then runs
Forgejo as UID/GID 1000. This requires a baseline namespace, rather than
Homepage's restricted policy. There is no service-account token, host networking
or privileged application container. `Recreate` avoids overlapping old and new
pods during a rollout. Do not scale above one replica with SQLite.

The chart's `initPreScript` refuses startup without an explicit restore-complete
marker, restored configuration, SQLite file at `/data/gitea/gitea.db`, repository
directory and explicit `DB_TYPE = sqlite3`. It runs before the chart scripts
change configuration or invoke database migration. If a data directory uses different
paths, ownership or database, stop and adjust the chart values before
restoring. Do not create an empty database to get past the check.

The values explicitly preserve the database, repository and application-data
paths; chart defaults would otherwise move them. The chart merges its settings
into the restored `app.ini` and preserves existing security and JWT secrets.
Automatic admin creation is disabled, so restored accounts remain authoritative.
No database or cache service is deployed. The chart also manages local cache,
queue and session defaults; review the rendered inline configuration against customisations in the
restored `app.ini` before startup. Do not put secrets in chart values.

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

A restore starts from an empty `storage` claim, for example after losing the
worker. Run from this repository on the laptop, with the working homelab `KUBECONFIG`
and the temporary zero-replica patch in place:

```sh
flux get kustomizations
kubectl -n forgejo get helmrelease,ocirepository,deployment,pvc,service
kubectl -n traefik get service
```

Expect the Deployment at zero replicas and both LoadBalancer Services assigned
`.200`. The `storage` claim stays Pending until a pod uses it. Forgejo HTTPS can
return 503 while it is stopped. Check that Homepage still serves normally.

The manual restore pod is excluded from Kustomize. It mounts the `storage` claim
in a temporary root container on `talos-worker-01`, which binds a new claim
there. It receives no API token. Forgejo must stay at zero replicas while it
runs.

```sh
kubectl apply -f kubernetes/apps/forgejo/restore-pod.yaml
kubectl -n forgejo wait --for=condition=Ready pod/forgejo-restore --timeout=5m
kubectl -n forgejo exec forgejo-restore -- df -h /data
```

## Restore the data directory

Build `forgejo-data.tar.gz` from the latest backup as in
[Rebuild the data directory](#rebuild-the-data-directory). It contains secrets:
keep it outside this checkout.

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
`app.ini`. Preserve the SQLite WAL/SHM companions if present and the numeric
ownership. Confirm the application data is accessible to UID/GID 1000.

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

Helm drift detection will revert a live Deployment scale. Suspend the root
Kustomization first so it cannot undo the application's suspension, then
suspend the Forgejo Kustomization. Other existing workloads and
Flux controllers keep running. Leave the HelmRelease running:

```sh
flux suspend kustomization flux-system
flux suspend kustomization forgejo
kubectl -n forgejo edit helmrelease forgejo
```

In the editor, remove only the Deployment replica-zero post-render patch under
`spec.postRenderers`. Keep the Service NodePort patch and `replicaCount: 1`.
The Helm controller will activate Forgejo without fighting a manual scale.
Remove the patch in Git too before resuming both Kustomizations.

```sh
flux reconcile helmrelease forgejo -n forgejo
kubectl -n forgejo rollout status deployment/forgejo --timeout=10m
kubectl -n forgejo logs deployment/forgejo -c forgejo --tail=100
curl --noproxy '*' --fail --show-error --resolve git.home.unbeholden.dev:443:192.168.4.200 https://git.home.unbeholden.dev/api/healthz
```

Do not bypass TLS verification. Log in with an existing account; verify
repository history, issues, attachments, packages and Actions settings. Clone
and push a disposable test repository over HTTPS and SSH. A dump does not hold
the SSH host keys, so update `known_hosts` deliberately.

The restored instance sends mail, runs scheduled tasks and delivers webhooks as
soon as it starts.

Flux fetches this repository over SSH with the host key stored in the
`flux-system/flux-system` Secret, so it rejects the new key too. Compare the
scanned key with the server's, replace `known_hosts` in the Secret without
touching the deploy key, and check that Flux fetches before resuming:

```sh
kubectl -n forgejo exec deploy/forgejo -c forgejo -- sh -c 'for k in /data/ssh/*.pub; do ssh-keygen -lf "$k"; done'
ssh-keyscan -p 222 git.home.unbeholden.dev 2>/dev/null | ssh-keygen -lf -
kh=$(ssh-keyscan -p 222 git.home.unbeholden.dev 2>/dev/null | base64 -w0)
kubectl -n flux-system patch secret flux-system --type merge -p "{\"data\":{\"known_hosts\":\"$kh\"}}"
flux reconcile source git flux-system
flux get sources git flux-system
```

Resume only once the GitRepository is Ready with the expected revision:

```sh
flux resume kustomization forgejo
flux resume kustomization flux-system
```

## Recovery and ongoing backups

Keep a copy of this repository and the deployment instructions outside Forgejo,
alongside the SOPS identity recovery described in `kubernetes/SECRETS.md`.
Recovering the Git server must not depend on fetching these manifests from it.

[K8up](../../infrastructure/k8up/) backs up Forgejo nightly at 01:00 UTC. It
runs `forgejo dump` inside the pod through the `k8up.io/backupcommand`
annotation and streams the tar into the restic repository `forgejo` on TrueNAS.
The PVC itself is excluded, so the live SQLite file is never copied. Retention
is 7 daily, 4 weekly and 3 monthly. The dump holds `app.ini`, the data
directory, repositories and `forgejo-db.sql`. It does not hold the SSH host keys
in `/data/ssh`, so after a restore clients see a new host key.

The restic password and rest-server credentials are in the shared
[`k8up-backup`](../../components/k8up-backup/) component and in Vaultwarden. Without them the backups cannot be read.

### Rebuild the data directory

To restore, fetch the dump on the laptop and rebuild the data-directory layout
that [Restore the data directory](#restore-the-data-directory) expects. Allow about three
times the dump size in free space. Set up restic as in
[Read a repository](../../infrastructure/k8up/README.md#read-a-repository)
with `repo=forgejo`, then:

```sh
d=$(mktemp -d); cd "$d"; mkdir -p dump out/gitea out/git
restic dump latest /forgejo-forgejo.tar > forgejo-dump.tar
tar -xf forgejo-dump.tar -C dump
cp -a dump/data/. out/gitea/
mv dump/repos out/git/repositories
find out/gitea -maxdepth 1 -name 'gitea.db*' -delete
{ echo 'BEGIN;'; cat dump/forgejo-db.sql; echo 'COMMIT;'; } |
  nix shell nixpkgs#sqlite --command sqlite3 out/gitea/gitea.db
tar -C out --owner=1000 --group=1000 --numeric-owner -czpf forgejo-data.tar.gz .
```

`restic ls latest` names the dump if `/forgejo-forgejo.tar` is not found.

To test a restore without the cluster, stop before the final `tar` and check
that the database is intact, that the repository count matches the live
instance and that a repository passes `git fsck`:

```sh
nix shell nixpkgs#sqlite --command sqlite3 out/gitea/gitea.db 'PRAGMA integrity_check;'
find out/git/repositories -mindepth 2 -maxdepth 2 -name '*.git' | wc -l
kubectl -n forgejo exec deploy/forgejo -- sh -c 'find /data/git/repositories -mindepth 2 -maxdepth 2 -name "*.git" | wc -l'
git -C "$(find out/git/repositories -mindepth 2 -maxdepth 2 -name '*.git' | head -1)" fsck
```

Test a restore after the first backup and after major Forgejo upgrades. Monitor
free disk space on the shared worker filesystem. `Retain`, Proxmox storage and a
surviving PVC are not backups.

## References

- [Forgejo Helm chart](https://code.forgejo.org/forgejo-helm/forgejo-helm)
- [Forgejo 17 Docker images and configuration](https://forgejo.org/docs/v17.0/admin/installation/docker/)
- [Forgejo backup and restore](https://forgejo.org/docs/latest/admin/setup/backup/)
- [Talos disk layout](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/storage-and-disk-management/disk-management/layout)
- [Talos local storage](https://docs.siderolabs.com/kubernetes-guides/csi/local-storage)
- [MetalLB IP sharing](https://metallb.io/usage/#ip-address-sharing)

# Groat

Groat runs at `https://groat.home.unbeholden.dev` through the private Traefik
listener at `192.168.4.200`, using its existing wildcard certificate.
The Deployment pins `ghcr.io/unbeholdendev/groat:v0.0.1-alpha15` and runs one
replica as UID/GID 1000. `Recreate` avoids overlapping pods during upgrades.
Do not scale it above one replica with SQLite.

## Storage

`/data/expenses.db` and its `.chatgpt` credential database live on the
`storage` claim from the `local-path` StorageClass (see
[Local Path Provisioner](../../infrastructure/local-path-provisioner/)). The
claim binds to the node that first runs the pod, `talos-worker-01`. Its 2 GiB
is not a quota; monitor free space on the worker. The namespace and claim opt
out of Flux pruning, and the StorageClass retains data when a claim is deleted.
This protects against resource removal, not loss or wiping of the worker.
There is no automatic failover to another node.

## Deploy and migrate

After merge, Flux discovers the Groat Kustomization:

```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization groat
kubectl -n groat rollout status deployment/groat --timeout=5m
kubectl -n groat get pvc,pod,service,ingress
```

Expect the claim Bound and the pod Ready. The probes check that `/` serves HTTP;
they do not prove that login, migration or database writes work.

For existing data, stop writes to the source and download its backup from
Settings > Backup and import. Keep that file outside this checkout. Use the
same or a newer application version on the destination. On the destination's
welcome screen, choose **Restore from a backup** before creating any account.
Restore is refused once anyone has signed up. Sign in with the restored account,
check expenses and members, and re-enter AI provider settings and reconnect
ChatGPT. Downloaded backups omit sign-ins, API tokens, chats, AI provider keys
and ChatGPT credentials. Keep the source stopped once the destination accepts
writes.

A fresh instance allows the first visitor to become admin or restore a backup.
Complete setup promptly from a trusted client before sharing the address.
With no source data, create the first admin account instead. You can test before
changing DNS using a temporary laptop hosts entry for the hostname at `.200`.
The Ingress is already reachable to clients of the shared listener at this point.

Add an exact AdGuard rewrite for `groat.home.unbeholden.dev` to `192.168.4.200`,
preserving other rewrites. Do not add a public proxy route or WAN forward.
The existing tailnet grant to `.200:443` also covers this hostname.
Verify trusted HTTPS, login, an expense, a pod restart and persistence from the
intended client network. Remove any temporary hosts entry.

## Releases and backups

Push a version tag in the Groat repository to publish its image through the
GitHub mirror. Ordinary development pushes do not deploy here. Renovate proposes
image tag updates, including alpha tags, using SemVer. Automerge is disabled:
merge the Renovate PR to let Flux deploy the release. A tag alone does not
change the running image.

Before every upgrade, download a backup and keep it outside the worker. Schema
migrations run on startup, so reverting an image tag alone may not undo an
upgrade. Recovery may need a fresh volume and restoration into a compatible
version. Test restore before relying on this instance for real data.

[K8up](../../infrastructure/k8up/) backs up Groat nightly at 01:00 UTC into the
restic repository `groat`. The pod annotation runs SQLite's `VACUUM INTO` through
`bun` and streams the copy, so the live file is never copied. Unlike a
downloaded backup, it keeps sign-ins, API tokens, chats and AI provider keys.
The `.chatgpt` credential file is not backed up; reconnect ChatGPT after
restoring onto a new volume.

To restore, set up restic as in
[Read a repository](../../infrastructure/k8up/README.md#read-a-repository)
with `repo=groat`, then replace the database with Groat stopped. Use the same
or a newer image than the backup. Data written since the backup is lost:

```sh
restic dump latest /groat-groat.sqlite > expenses.db
flux suspend kustomization groat
kubectl -n groat scale deployment/groat --replicas=0
kubectl -n groat wait --for=delete pod -l app.kubernetes.io/name=groat --timeout=2m
kubectl -n groat run restore --image=docker.io/library/busybox:1.38.0 --restart=Never --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"restore","image":"docker.io/library/busybox:1.38.0","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"storage"}}]}}'
kubectl -n groat wait --for=condition=Ready pod/restore --timeout=2m
kubectl -n groat exec -i restore -- sh -ec 'rm -f /data/expenses.db-wal /data/expenses.db-shm; cat > /data/expenses.db' < expenses.db
kubectl -n groat delete pod restore
flux resume kustomization groat
kubectl -n groat rollout status deployment/groat --timeout=5m
```

Keep downloading a backup before upgrades. A retained PVC is not a backup.

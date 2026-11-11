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

The `copy-data` init container copies data from the old `data` claim, a PV on the
Talos user volume `/var/mnt/groat`. Talos reset that directory to root
ownership after trimming EPHEMERAL, which stopped SQLite creating journal files
there. The copy runs while the old pod is stopped and only once: it marks the
old volume with `.copied-to-local-path`. A follow-up change removes the init
container, the old PV and claim, and `worker-volume.patch.yaml`.

## Deploy and migrate

After merge, Flux discovers the Groat Kustomization:

```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization groat
kubectl -n groat rollout status deployment/groat --timeout=5m
kubectl -n groat get pvc,pod,service,ingress
kubectl get pv groat-data
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

Automated off-worker backups are pending K8up PR #84 and a Groat backup
integration. Until then, download backups regularly and after important changes.
Do not copy a live SQLite file as a backup. A retained PVC is not a backup.

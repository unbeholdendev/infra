# K8up backups

K8up 2.16 backs up application data with restic. Flux rebuilds every cluster
object from Git, so only data needs a backup. Each app namespace holds its own
`Schedule`, and each app has one restic repository on TrueNAS, served by restic
rest-server at `http://192.168.5.2:30800/<app>`.

K8up backs up every PVC in a namespace with a `Schedule` unless the PVC has
`k8up.io/backup: "false"`. Prefer an app's own dump through the pod annotations
`k8up.io/backupcommand` and `k8up.io/file-extension`: a live database file is not
a consistent backup. See [Forgejo](../../apps/forgejo/) for the pattern.

## TrueNAS rest-server

Create dataset `storage/apps/restic` and install rest-server
(`docker.io/restic/rest-server`, tag `0.14.0`) with host path
`/mnt/storage/apps/restic` as its data volume and host port 30800.

All apps share one rest-server user, `k8up`. In the app's container shell:

```sh
create_user k8up
```

Its user and password, and the `RESTIC_PASSWORD` shared by every repository,
are in the `backup` Secret of the [`k8up-backup`](../../components/k8up-backup/)
component, which each backed-up app lists under `components` in its
`kustomization.yaml`. Any app's credentials can delete every repository, so add
a daily periodic snapshot task on `storage/apps/restic`, kept for 14 days.

The router must allow the cluster nodes to reach `192.168.5.2` on TCP 30800.

## Verify after merge

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n k8up get helmrelease,pods
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n forgejo get schedule,backup,snapshots
```

To run a backup now rather than wait for the schedule:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n forgejo create -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Backup
metadata:
  generateName: manual-
spec:
  backend:
    repoPasswordSecretRef: {name: backup, key: RESTIC_PASSWORD}
    rest:
      url: http://192.168.5.2:30800/forgejo
      userSecretRef: {name: backup, key: REST_USER}
      passwordSecretReg: {name: backup, key: REST_PASSWORD}
EOF
```

## References

- [K8up documentation](https://docs.k8up.io/)
- [Annotations](https://docs.k8up.io/k8up/references/annotations.html)
- [restic rest-server](https://github.com/restic/rest-server)

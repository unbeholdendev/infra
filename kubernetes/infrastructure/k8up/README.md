# K8up backups

K8up 2.16 backs up application data with restic. Flux rebuilds every cluster
object from Git, so only data needs a backup. Each app namespace holds its own
`Schedule`, and each app has one restic repository on TrueNAS, served by restic
rest-server at `http://192.168.5.2:30800/<app>`.

K8up backs up every PVC in a namespace with a `Schedule` unless the PVC has
`k8up.io/backup: "false"`. Prefer an app's own dump through the pod annotations
`k8up.io/backupcommand` and `k8up.io/file-extension`: a live database file is not
a consistent backup. K8up splits the command on spaces and quotes and runs it
without a shell, and stores its stdout as `/<namespace>-<container><extension>`.

Forgejo, Groat and Radicale are backed up. ntfy holds only cached messages,
and Homepage and Renovate keep no state.

To back up an app:

1. List `../../components/k8up-backup` under `components` in its
   `kustomization.yaml`. The component adds the `backup` Secret, the nightly
   `Schedule` and a restricted `PodConfig` for K8up's job pods. The repository
   is named after the app's Namespace.
2. Add the backup annotations to the pod and `k8up.io/backup: "false"` to the PVC.
3. Add `k8up` to `dependsOn` in its Flux Kustomization under
   `clusters/homelab`, so the CRDs exist first.

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

To run a backup now rather than wait for the schedule, replacing `forgejo`
in both places with the app:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n forgejo create -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Backup
metadata:
  generateName: manual-
spec:
  podConfigRef: {name: backup}
  backend:
    repoPasswordSecretRef: {name: backup, key: RESTIC_PASSWORD}
    rest:
      url: http://192.168.5.2:30800/forgejo
      userSecretRef: {name: backup, key: REST_USER}
      passwordSecretReg: {name: backup, key: REST_PASSWORD}
EOF
```

## Read a repository

On the laptop, from this checkout, with `repo` set to the app:

```sh
umask 077
f=kubernetes/components/k8up-backup/backup.sops.yaml
export RESTIC_PASSWORD="$(sops -d --extract '["stringData"]["RESTIC_PASSWORD"]' $f)"
rest_pw="$(sops -d --extract '["stringData"]["REST_PASSWORD"]' $f)"
export RESTIC_REPOSITORY="rest:http://k8up:${rest_pw}@192.168.5.2:30800/$repo"
alias restic='nix shell nixpkgs#restic --command restic'
restic snapshots
```

A REST password containing `@`, `:` or `/` must be percent-encoded in the URL.

## References

- [K8up documentation](https://docs.k8up.io/)
- [Annotations](https://docs.k8up.io/k8up/references/annotations.html)
- [restic rest-server](https://github.com/restic/rest-server)

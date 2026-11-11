# Local Path Provisioner

[Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
gives app PVCs a directory each under `/var/mnt/local-path-provisioner` on the
node that first runs the claiming pod. Request it with
`storageClassName: local-path`. This is the setup the
[Talos local storage guide](https://docs.siderolabs.com/kubernetes-guides/csi/local-storage)
recommends.

Talos owns the volume root and resets it to `root:root 0755` whenever it
reconciles the volume, for example after trimming EPHEMERAL. Pointing a PV at
a Talos user volume root therefore breaks apps that create files there. The
provisioner keeps each claim in `<namespace>/<claim>/` below that root, created
`0777`, which Talos leaves alone.

The StorageClass uses `Retain`, so deleting a claim keeps its directory on the
node; delete the directory by hand once you no longer need it. Data is not
replicated and stays on its node; it is not a backup. Claims advertise a size,
but nothing enforces it: watch free space on the worker's EPHEMERAL filesystem.

The provisioner runs privileged helper pods with `hostPath` mounts, so its
namespace is the only one with a privileged Pod Security level.

## Prepare the node

Before merging, with the working `TALOSCONFIG`:

```sh
talosctl --nodes 192.168.4.133 patch mc --patch @kubernetes/infrastructure/local-path-provisioner/worker-volume.patch.yaml
talosctl --nodes 192.168.4.133 get volumestatus u-local-path-provisioner
talosctl --nodes 192.168.4.133 get mountstatus u-local-path-provisioner
```

Keep the patch in the worker's machine configuration when reprovisioning.

## Verify

```sh
flux reconcile kustomization local-path-provisioner --with-source
kubectl -n local-path-storage get helmrelease,pods
kubectl get storageclass local-path
```

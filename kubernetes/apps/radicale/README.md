# Radicale

Radicale serves calendars and contacts at `https://cal.home.unbeholden.dev` on
the private Traefik listener at `192.168.4.200`, using the wildcard certificate.
It runs one replica as UID/GID 1000 and keeps collections on the `storage`
claim from the `local-path` StorageClass, on `talos-worker-01`.

AdGuard rewrites the name to `.200`. calrs on Giran reaches it over the tailnet
with an `extra_hosts` entry for the name; Traefik routes by hostname, so clients
must use the name, not the IP.

## Users

Radicale authenticates users itself, against an htpasswd file. The config in
`config.yaml` is public; the htpasswd file is the SOPS Secret `users.sops.yaml`,
key `users`. `autodetect` accepts bcrypt hashes and plain-text passwords.

```sh
sops edit kubernetes/apps/radicale/users.sops.yaml
```

Merge the change to `main`, then let Flux apply it and roll the pod, which reads
the file only at startup:

```sh
flux reconcile kustomization radicale --with-source
kubectl -n radicale rollout restart deployment/radicale
```

Hash a new password with `nix shell nixpkgs#apacheHttpd --command htpasswd -nB NAME`.
Each user's collections live under `collections/collection-root/<name>/`, so
renaming a user orphans their data.

## Deploy and test

```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization radicale
kubectl -n radicale rollout status deployment/radicale --timeout=5m
curl -s -u NAME -X PROPFIND -H 'Depth: 1' https://cal.home.unbeholden.dev/NAME/ | grep -o '<href>[^<]*'
```

The last command lists the user's calendars and address books.

## Backups

[K8up](../../infrastructure/k8up/) backs up Radicale nightly at 01:00 UTC. The
pod annotation tars `/var/lib/radicale` inside the pod, holding a shared lock on
Radicale's `.Radicale.lock` so no write runs mid-archive, and streams it into
the restic repository `radicale`. To fetch the latest, set up restic as in
[Read a repository](../../infrastructure/k8up/README.md#read-a-repository)
with `repo=radicale`:

```sh
restic dump latest /radicale-radicale.tar > radicale-DATE.tar
```

Before upgrades, a copy taken now is quicker:

```sh
kubectl -n radicale exec deploy/radicale -- flock -s /var/lib/radicale/collections/.Radicale.lock tar -C /var/lib/radicale -cf - . > radicale-$(date +%F).tar
```

To restore, stop Radicale so nothing writes, replace the collections from a
helper pod on the same claim, then let Flux start it again. Data written since
the backup is lost:

```sh
flux suspend kustomization radicale
kubectl -n radicale scale deployment/radicale --replicas=0
kubectl -n radicale wait --for=delete pod -l app.kubernetes.io/name=radicale --timeout=2m
kubectl -n radicale run restore --image=docker.io/library/busybox:1.38.0 --restart=Never --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"restore","image":"docker.io/library/busybox:1.38.0","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"data","mountPath":"/var/lib/radicale"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"storage"}}]}}'
kubectl -n radicale wait --for=condition=Ready pod/restore --timeout=2m
kubectl -n radicale exec -i restore -- sh -ec 'rm -rf /var/lib/radicale/collections; tar -xf - -C /var/lib/radicale' < radicale-DATE.tar
kubectl -n radicale delete pod restore
flux resume kustomization radicale
kubectl -n radicale rollout status deployment/radicale --timeout=5m
```

A retained PVC is not a backup.

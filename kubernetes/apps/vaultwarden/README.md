# Vaultwarden

Vaultwarden serves `https://vw.home.unbeholden.dev` on the private Traefik
listener at `192.168.4.200`, using the wildcard certificate. It is not proxied
publicly. It runs one replica as UID/GID 1000 and keeps its SQLite database,
attachments, sends and `rsa_key.pem` on the `storage` claim from the
`local-path` StorageClass, on `talos-worker-01`.

Signups are off and there is no `ADMIN_TOKEN`, so the admin page is disabled.
To add a user, briefly set `SIGNUPS_ALLOWED` to `"true"`. `DOMAIN` must match the
URL clients use: attachment and Send links and WebAuthn 2FA are built from it.

## Deploy and test

```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization vaultwarden
kubectl -n vaultwarden rollout status deployment/vaultwarden --timeout=5m
curl --fail --resolve vw.home.unbeholden.dev:443:192.168.4.200 https://vw.home.unbeholden.dev/alive
```

## Backups

[K8up](../../infrastructure/k8up/) backs up Vaultwarden nightly at 01:00 UTC.
The pod annotation runs `vaultwarden backup`, a consistent copy of the live
database, and streams a tar of it with the rest of `/data`, without the icon
cache, into the restic repository `vaultwarden`. In the tar the database is
`db_<timestamp>.sqlite3`. To fetch the latest, set up restic as in
[Read a repository](../../infrastructure/k8up/README.md#read-a-repository)
with `repo=vaultwarden`:

```sh
restic dump latest /vaultwarden-vaultwarden.tar > vaultwarden-DATE.tar
```

## Restore

Stop Vaultwarden, replace `/data` from a helper pod on the same claim, rename
the database copy, then let Flux start it again. Data written since the backup
is lost. Suspend the root Kustomization first so it cannot undo Vaultwarden's
suspension:

```sh
flux suspend kustomization flux-system
flux suspend kustomization vaultwarden
kubectl -n vaultwarden scale deployment/vaultwarden --replicas=0
kubectl -n vaultwarden wait --for=delete pod -l app.kubernetes.io/name=vaultwarden --timeout=2m
kubectl -n vaultwarden run restore --image=docker.io/library/busybox:1.38.0 --restart=Never --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"restore","image":"docker.io/library/busybox:1.38.0","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"storage"}}]}}'
kubectl -n vaultwarden wait --for=condition=Ready pod/restore --timeout=2m
kubectl -n vaultwarden exec -i restore -- sh -ec 'cd /data; find . -mindepth 1 -delete; tar -xf -; set -- db_*.sqlite3; [ -f "$1" ] && mv "$1" db.sqlite3; ls -la' < vaultwarden-DATE.tar
kubectl -n vaultwarden delete pod restore
flux resume kustomization vaultwarden
flux resume kustomization flux-system
kubectl -n vaultwarden rollout status deployment/vaultwarden --timeout=5m
```

The listing must show `db.sqlite3` and `rsa_key.pem`. A new `rsa_key.pem`
logs every client out.

## Cut over from aden

1. On aden, stop the container, then archive its bind mount without the icon
   cache and the admin page's `config.json`, which would override the
   environment, including `DOMAIN`:
   `tar -C /root/vw-data -cf vaultwarden-aden.tar --exclude=./icon_cache --exclude=./config.json --exclude=./.DS_Store .`
2. Restore that tar with the steps above. It already holds `db.sqlite3`.
3. Log in to the web vault through the `--resolve` address and open an item
   with an attachment, if any.
4. Add an exact AdGuard rewrite for `vw.home.unbeholden.dev` to
   `192.168.4.200`. Clients keep the same server URL; the shared user's tailnet
   grant already covers `.200:443`.
5. Remove the container and its proxy route on aden. Then drop `aden:443` from
   the shared user's grant in `playbooks/files/headscale/policy.hujson`.

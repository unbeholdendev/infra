# Radicale

Radicale serves calendars and contacts at `https://cal.home.unbeholden.dev` on
the private Traefik listener at `192.168.4.200`, using the wildcard certificate.
It runs one replica as UID/GID 1000 and keeps collections on the `storage`
claim from the `local-path` StorageClass, on `talos-worker-01`.

Radicale authenticates users itself, against an htpasswd file. The config in
`config.yaml` is public; the htpasswd file is the SOPS Secret `users.sops.yaml`,
key `users`. Both are mounted read-only at `/etc/radicale`. Roll the pod after
changing either: `kubectl -n radicale rollout restart deployment/radicale`.

## Create the users Secret

Before merging, on the laptop, from this checkout, with aden's htpasswd file
copied outside it (the file `htpasswd_filename` names in aden's
`./config/config`):

```sh
kubectl create secret generic radicale-users --from-file=users=/secure/path/users --dry-run=client -o yaml \
  | sops encrypt --filename-override kubernetes/apps/radicale/users.sops.yaml --input-type yaml --output-type yaml /dev/stdin \
  > kubernetes/apps/radicale/users.sops.yaml
```

Check the file shows `ENC[` under `data`, then commit it. Plaintext never
touches the checkout.

Compare aden's `./config/config` with `config.yaml` too. Carry over any
`[rights]`, `[storage] hook` or other non-default settings; aden's paths do not
apply here. aden runs `:latest`, which tracks Radicale's main branch; this pins
`3.9.0`. If aden's version is newer, check the changelog for storage changes.

## Deploy and migrate

```sh
flux reconcile kustomization flux-system --with-source
kubectl -n radicale rollout status deployment/radicale --timeout=5m
kubectl -n radicale exec deploy/radicale -- sh -c 'd=/var/lib/radicale/collections/collection-root; test ! -d $d || test -z "$(ls -A $d)"'
```

Radicale creates an empty `collection-root` on startup. Stop if the last
check fails: it means some user's data is already there. Then stop Radicale on aden so nothing writes
while copying, and stream its data directory into the pod:

```sh
ssh aden 'cd /path/to/radicale && docker compose stop radicale && tar -C data -cf - .' \
  | kubectl -n radicale exec -i deploy/radicale -- tar -xf - -C /var/lib/radicale
kubectl -n radicale rollout restart deployment/radicale
kubectl -n radicale rollout status deployment/radicale --timeout=5m
curl --fail -u USER --resolve cal.home.unbeholden.dev:443:192.168.4.200 https://cal.home.unbeholden.dev/USER/
```

The data should hold a `collections/` directory. Files land owned by UID 1000.
Log in to `/.web/` with the same trick and check each calendar and address book.

## Cut over

1. Add an exact AdGuard rewrite for `cal.home.unbeholden.dev` to
   `192.168.4.200`, replacing the one to aden.
2. Apply the Headscale policy. It grants `amberdust@` `192.168.4.200:443`,
   which reaches every app behind the shared listener, not only Radicale.
3. On Giran, point calrs at `https://cal.home.unbeholden.dev`. Traefik routes
   by hostname, so the old IP-and-port URL will not work. Giran's `.200:443`
   grant already covers it; the name must resolve to `.200` there, as for
   Forgejo.
4. Check sync from each client. Keep aden's Radicale stopped.
5. Remove the `cal` site and the `:5233` listener from Caddy on aden. Then drop
   `aden:5233` from `tag:giran` in `playbooks/files/headscale/policy.hujson`
   and apply it.

Before step 1, rollback is starting aden's Radicale again. Once clients write
to the cluster, copy the data back first.

## Backups

None automatic yet; they wait on K8up (#84). Until then, before upgrades, copy
the data out:

```sh
kubectl -n radicale exec deploy/radicale -- tar -C /var/lib/radicale -cf - . > radicale-$(date +%F).tar
```

A retained PVC is not a backup.

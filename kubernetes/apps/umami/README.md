# Umami

Umami serves `https://umami.unbeholden.dev` on the private Traefik listener at
`192.168.4.200`, with its own Let's Encrypt certificate, as ntfy does. AdGuard
rewrites the name to `.200`; public DNS points at Giran, which proxies over the
tailnet to `.200`, so sites' visitors can load the tracker.

Postgres runs as its own Deployment in the namespace, on the `postgres` claim
from the `local-path` StorageClass on `talos-worker-01`. The SOPS Secret
`secret.sops.yaml` holds the database password, the matching `DATABASE_URL`
and `APP_SECRET`. Umami applies its database migrations on start.

## Backups

[K8up](../../infrastructure/k8up/) backs up Umami nightly at 01:00 UTC. The
Postgres pod annotation runs `pg_dump -Fc` and streams it into the restic
repository `umami`; the claim itself is excluded. To fetch the latest, set up
restic as in [Read a repository](../../infrastructure/k8up/README.md#read-a-repository)
with `repo=umami`:

```sh
restic dump latest /umami-postgres.dump > umami.dump
```

To restore a dump, load it into an empty database with Umami stopped. Suspend
the root Kustomization first so it cannot undo Umami's suspension mid-restore:

```sh
flux suspend kustomization flux-system
flux suspend kustomization umami
kubectl -n umami scale deployment/umami --replicas=0
kubectl -n umami wait --for=delete pod -l app.kubernetes.io/name=umami --timeout=2m
kubectl -n umami exec deploy/postgres -- psql -U umami -d postgres -c 'DROP DATABASE umami WITH (FORCE)' -c 'CREATE DATABASE umami'
kubectl -n umami exec -i deploy/postgres -- pg_restore -U umami -d umami --no-owner --exit-on-error < umami.dump
flux resume kustomization umami
flux resume kustomization flux-system
kubectl -n umami rollout status deployment/umami --timeout=5m
```

## Deploy and test

```sh
flux reconcile kustomization flux-system --with-source
kubectl -n umami wait --for=condition=Ready certificate/umami --timeout=20m
kubectl -n umami rollout status deployment/postgres deployment/umami --timeout=5m
curl --fail --resolve umami.unbeholden.dev:443:192.168.4.200 https://umami.unbeholden.dev/api/heartbeat
```

## Cut over from aden

1. On aden, stop the app so no events arrive mid-copy, then dump:
   `docker compose stop umami && docker compose exec -T db pg_dump -U umami -d umami -Fc > umami.dump`
2. Restore it with the commands under Backups, then log in with the old
   accounts at `https://umami.unbeholden.dev` via the `--resolve` address.
3. Add an exact AdGuard rewrite for `umami.unbeholden.dev` to `192.168.4.200`.
4. On Giran, point the Dokploy route for `umami.unbeholden.dev` at
   `https://192.168.4.200`, keeping the Host header, with
   `serverName: umami.unbeholden.dev` in its servers transport.
5. Check a tracked site records a visit with the right country, then remove
   Umami from aden and drop `aden:3123` from `tag:giran` in
   `playbooks/files/headscale/policy.hujson`.

The new `APP_SECRET` logs everyone out once.

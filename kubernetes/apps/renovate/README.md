# Renovate

A CronJob runs Renovate daily at 05:17 UTC and opens update PRs. It never merges
them. Merging a Kubernetes update lets Flux deploy it, so review chart release
notes and CRD steps first.

## Selecting repositories

Renovate updates an `unbeholden` repository only when both are true:

- the `renovate` account has write access to it
- it has a `renovate.json` on its default branch

Remove either to opt a repository out. Never add the account to a team with
access to every repository. Each repository's own config sets its limits; infra
allows three open PRs, and the Dependency Dashboard issue lists the rest.

## Credentials

Before merging the first deployment:

1. Create a `renovate` Forgejo account with a full name and email, and give it
   write access to the selected repositories.
2. As that account, create a token for all repositories with `write:repository`,
   `write:issue`, `read:user` and `read:organization`.
3. Create a GitHub classic token with no scopes, for public release lookups.
4. From the repository root, run `sops edit kubernetes/apps/renovate/env.sops.yaml`
   and replace the content with:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: renovate-env
   type: Opaque
   stringData:
     RENOVATE_TOKEN: <Forgejo token>
     RENOVATE_GITHUB_COM_TOKEN: <GitHub token>
   ```

## Operating

```sh
kubectl -n renovate create job --from=cronjob/renovate renovate-manual
kubectl -n renovate logs -f job/renovate-manual
kubectl -n renovate delete job renovate-manual
```

Set `spec.suspend: true` on the CronJob to pause updates. A failed run raises no
alert: check the last Job if the Dependency Dashboard goes stale.

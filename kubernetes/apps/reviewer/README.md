# reviewer

The Forgejo review bot from `unbeholden/reviewer`. Forgejo reaches it inside
the cluster at `http://reviewer.reviewer.svc.cluster.local:3000/webhook`; it has
no ingress.

The image is pinned by digest to the `latest` tag that the repository's
`build` workflow pushes. Renovate opens a PR when that digest changes.

The PR under review is untrusted input, and the cluster enforces no network
policies, so the pod can reach the LAN and other Services. Give its Forgejo
account access only to the repositories it reviews.

The server exits at startup without a usable subscription login in the
`credentials` claim, which holds `auth.json` and `device-id`. Both stay out of
Git. The refresh token rotates, so only one process may use the login at a
time: stop the Deployment, and Flux with it, before touching the claim.

## Credentials

`env.sops.yaml` holds the bot account's token and the webhook secret. Change
them with `sops edit kubernetes/apps/reviewer/env.sops.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: reviewer-env
type: Opaque
stringData:
  FORGEJO_TOKEN: <bot token>
  WEBHOOK_SECRET: <webhook secret>
```

## Login

To check the login, or sign in again when it can no longer refresh:

1. Stop the bot, and Flux so it doesn't restore the replica:
   ```sh
   flux suspend kustomization reviewer
   kubectl -n reviewer scale deploy/reviewer --replicas=0
   kubectl -n reviewer wait --for=delete pod -l app.kubernetes.io/name=reviewer --timeout=120s
   ```
   Go on only once the wait succeeds.
2. Start a helper pod on the claim:
   ```sh
   IMAGE=$(kubectl -n reviewer get deploy reviewer -o jsonpath='{.spec.template.spec.containers[0].image}')
   kubectl -n reviewer run creds --restart=Never --image="$IMAGE" --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"fsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"creds","image":"'"$IMAGE"'","command":["sleep","1800"],"env":[{"name":"FORGEJO_URL","value":"https://git.home.unbeholden.dev"}],"envFrom":[{"secretRef":{"name":"reviewer-env"}}],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"credentials","mountPath":"/app/credentials"}]}],"volumes":[{"name":"credentials","persistentVolumeClaim":{"claimName":"credentials"}}]}}'
   kubectl -n reviewer wait --for=condition=Ready pod/creds
   ```
3. Check or renew the login. It makes no model request; if it prints a
   sign-in URL, open it, sign in and paste the final redirect URL back:
   ```sh
   kubectl -n reviewer exec -it creds -- bun src/login.ts
   kubectl -n reviewer delete pod creds
   ```
   To force a new sign-in, run `kubectl -n reviewer exec creds -- rm
   /app/credentials/auth.json` first. Keep `device-id`.
4. Resume Flux, which scales the bot back to one:
   ```sh
   flux resume kustomization reviewer
   kubectl -n reviewer rollout status deploy/reviewer
   ```

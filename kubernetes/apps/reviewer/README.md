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

Before merging the first deployment, from the repository root, run
`sops edit kubernetes/apps/reviewer/env.sops.yaml` and set the bot account's
token and the webhook secret, the values from aden's `.env`:

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

## Move from aden

OpenAI rotates the refresh token, so the old and new copies must never run at
once.

1. On aden, in the reviewer clone: `docker compose down`.
2. Merge. The pod restarts until step 5.
3. Stop the bot, and Flux so it doesn't restore the replica:
   ```sh
   flux suspend kustomization reviewer
   kubectl -n reviewer scale deploy/reviewer --replicas=0
   kubectl -n reviewer wait --for=delete pod -l app.kubernetes.io/name=reviewer --timeout=120s
   ```
   Go on only once the wait succeeds.
4. Start a helper pod on the claim:
   ```sh
   IMAGE=$(kubectl -n reviewer get deploy reviewer -o jsonpath='{.spec.template.spec.containers[0].image}')
   kubectl -n reviewer run creds --restart=Never --image="$IMAGE" --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"fsGroup":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"creds","image":"'"$IMAGE"'","command":["sleep","1800"],"envFrom":[{"secretRef":{"name":"reviewer-env"}}],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"credentials","mountPath":"/app/credentials"}]}],"volumes":[{"name":"credentials","persistentVolumeClaim":{"claimName":"credentials"}}]}}'
   kubectl -n reviewer wait --for=condition=Ready pod/creds
   ```
5. Copy the login from aden, then remove the local copies:
   ```sh
   umask 077 && mkdir reviewer-credentials
   scp 'root@192.168.4.12:<clone>/credentials/{auth.json,device-id}' reviewer-credentials/
   kubectl -n reviewer cp reviewer-credentials/auth.json creds:/app/credentials/auth.json
   kubectl -n reviewer cp reviewer-credentials/device-id creds:/app/credentials/device-id
   rm -r reviewer-credentials
   kubectl -n reviewer exec creds -- bun src/login.ts
   kubectl -n reviewer delete pod creds
   ```
   `login.ts` checks the login without a model request. If it prints a
   sign-in URL, follow it as the reviewer's README describes; run the command
   with `-it` to paste the result.
6. Resume Flux, which scales the bot back to one, and check its log:
   ```sh
   flux resume kustomization reviewer
   kubectl -n reviewer rollout status deploy/reviewer
   kubectl -n reviewer logs deploy/reviewer
   ```
7. In the `unbeholden` org's webhook, set the URL to
   `http://reviewer.reviewer.svc.cluster.local:3000/webhook` and use "Test
   delivery". If Forgejo refuses the host, add it to `ALLOWED_HOST_LIST` under
   `[webhook]` in its `app.ini`.
8. Open or push to a PR and check for the 👀 reaction and a review. Then delete
   the reviewer clone and image on aden.

## Fresh login

Stop the bot and start the helper pod as in steps 3 and 4, then
`kubectl -n reviewer exec -it creds -- bun src/login.ts`, follow the URL, paste
the redirect, delete the pod and resume as in step 6.

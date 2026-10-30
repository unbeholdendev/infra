# LiteLLM trial

LiteLLM runs at `https://llm.home.unbeholden.dev` through the existing private
Traefik listener, `192.168.4.200`. Start with Claude Code subscription forwarding.
Pi's native `openai` provider stays direct until its subscription path is proven
compatible. Client configuration belongs in dotfiles, separately from this
infrastructure change.

The official monolithic chart owns the proxy, ingress and migration job.
`release.yaml` pins chart 1.106.6 and image v1.106.6 separately, each by digest.
Kustomize creates their shared service account before Helm's pre-install hook;
neither process receives a Kubernetes API token. There is one
proxy replica, one worker and no Redis, response cache, model fallback or
server-side provider credential. PostgreSQL has one instance and its own retained
local volume.

## Storage and recovery limits

The PostgreSQL PV advertises 4 GiB on `talos-worker-01`, at
`/var/mnt/litellm-postgres`. It needs the manual Talos directory-volume patch
before startup. There is no StorageClass or dynamic provisioner. Like Forgejo,
this directory shares the worker's EPHEMERAL filesystem with images and logs.
The 4 GiB claim is a planning allowance, not a reservation or enforced quota.
On 30 October 2026 the worker reported 25.79 GB free of 31.98 GB on `/var`.

A dedicated PostgreSQL Deployment avoids adding an operator for one trial
application. CloudNativePG would manage database lifecycle and backup workflows,
but would add CRDs, an operator and backup integration without fixing this
worker's storage or failure domain. Reconsider it when more applications need
PostgreSQL or recovery requirements grow.

Individual request logs expire after 3 days, with cleanup scheduled hourly
while the proxy is healthy. Daily usage aggregates are stored separately and
are not expired by this setting; key/model/date/token/spend totals can remain
beyond 3 days. This is request-log retention, not a limit on all usage history. Request and response bodies are stored for debugging, so
prompts, file contents and tool results stay in PostgreSQL until cleanup.
LiteLLM drops raw request headers and masks credential-named body fields.
Stored metadata uses an allow-list that keeps client identity, OAuth
attribution and usage details but excludes error bodies and tracebacks. Failed requests keep
their outcome, without stored error diagnostics. Review console logs separately;
these database controls do not prove every upstream exception is safe to log.
Rows can remain until the next cleanup run. Deleting rows does
not immediately return PostgreSQL files to the filesystem; vacuum normally
makes space reusable inside the database. Check actual disk growth.

Backups are deliberately excluded from this trial at the owner's request.
`Retain` and disabled Flux pruning protect the namespace, PV and claim from
ordinary application removal; they do not protect against worker loss, disk
failure or database corruption. There is no tested database restore procedure.
Worker loss may lose virtual keys, usage history and database-held settings.
Git and the independently recoverable SOPS identity preserve the initial
credentials and declarative configuration, not the database contents.

Never change `LITELLM_SALT_KEY` on an existing database. Preserve it with the
master key and database credentials. Changing Secret values does not change an
already initialised PostgreSQL password. Rotate database roles and their Secret
references together. `POSTGRES_DB`, `POSTGRES_USER` and `POSTGRES_PASSWORD`
run only when initialising an empty data directory; LiteLLM's migration job
then creates and updates the application schema.

## Prepare and deploy

Run these on the laptop with the working `TALOSCONFIG` and `KUBECONFIG`.
Do not apply the Talos document with `kubectl` or include it in Kustomize.

```sh
talosctl --nodes 192.168.4.133 patch mc --patch @kubernetes/apps/litellm/worker-volume.patch.yaml
talosctl --nodes 192.168.4.133 get volumestatus u-litellm-postgres
talosctl --nodes 192.168.4.133 get mountstatus u-litellm-postgres
```

Wait for the volume to be ready at `/var/mnt/litellm-postgres`. Keep this document
in the worker's machine configuration when reprovisioning. It creates no
partition and formats no disk.

After merge, Flux discovers `clusters/homelab/litellm.yaml`. Its root patch adds
SOPS decryption using `flux-system/sops-age`; bootstrap and key recovery are in
[`../../SECRETS.md`](../../SECRETS.md).

```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization litellm
flux get kustomizations
kubectl -n litellm get ocirepository,helmrelease,deployment,job,pvc,ingress
kubectl get pv litellm-postgres
kubectl -n litellm rollout status deployment/postgres --timeout=5m
kubectl -n litellm logs deployment/postgres --tail=50
```

Expect the claim Bound, PostgreSQL and proxy Ready, the migration job Complete,
and the HelmRelease Ready. Inspect migration and proxy
logs locally for errors; do not paste credentials, request headers or payloads
into issues or chat. A successful Helm render does not prove migrations work.

Add an exact private DNS rewrite for `llm.home.unbeholden.dev` to
`192.168.4.200`, preserving the wildcard and other services. Do not add a WAN
forward or a public reverse-proxy route. Headscale's existing `tag:giran` grant
to `.200:443` covers every hostname on this listener, so LiteLLM authentication
must remain enabled.

Test from the intended LAN or tailnet client network without disabling
certificate checks:

```sh
curl --noproxy '*' --fail --show-error \
  --resolve llm.home.unbeholden.dev:443:192.168.4.200 \
  https://llm.home.unbeholden.dev/health/readiness
curl --noproxy '*' --fail --show-error \
  https://llm.home.unbeholden.dev/health/readiness
curl --noproxy '*' --silent --show-error --output /dev/null --write-out '%{http_code}\n' \
  -H 'Content-Type: application/json' \
  --data '{"model":"anthropic/claude-sonnet-4-6","messages":[{"role":"user","content":"hello"}],"max_tokens":16}' \
  https://llm.home.unbeholden.dev/v1/messages
```

The unauthenticated inference request must return 401 or 403, never a streamed
response. Repeat with an invalid gateway key. Public health probes may be
unauthenticated; they are not an inference access test. Check Homepage and
Forgejo still work.

## Client keys and subscription checks

Use the master key only for API administration. `disable_env_credential_login`
turns off its `/ui` login, so log in with a database-held admin account. That
account has no backup: if the database is lost, remove the setting to log in
with the master key and create another. Retrieve the key from
`litellm-masterkey` without putting it in Git, shell history or chat. Create
separate virtual keys named `claude-code` and `pi`, restricted to the configured Anthropic models. Keep the Pi key unused
while native OpenAI support is unresolved. Put client keys in the clients' local
secret stores, never use the master key for inference clients, and do not copy
OAuth files to the cluster.

The separate dotfiles change must follow the official
[Claude Code subscription guide](https://docs.litellm.ai/docs/tutorials/claude_code_max_subscription):
use the proxy root as `ANTHROPIC_BASE_URL`, retain client OAuth in
`Authorization`, and supply `x-litellm-api-key: Bearer <virtual-key>` separately.
Preserve any existing custom headers. Do not substitute an API key,
`ANTHROPIC_AUTH_TOKEN` or `apiKeyHelper` for the subscription login. Inspect
existing settings before changing them; no new login is required by this
infrastructure configuration.

Use direct Anthropic routing on `/v1/messages`, not `/anthropic` pass-through,
Bedrock or Vertex. The auxiliary `/v1/messages/count_tokens` route does not have
the same subscription-forwarding contract. With no configured provider API key,
an unsupported auxiliary call must fail rather than incur API billing. Whether
Claude Code tolerates that failure needs live testing.

Before accepting the trial, use the existing client subscription for all of:

- A streamed text reply and a harmless local tool round-trip, such as reading a
  disposable file and reporting its contents. Tool execution stays on the client.
- A repeated request that exercises provider prompt-cache accounting, with
  LiteLLM response caching still off.
- A long response lasting beyond three minutes, plus a cancelled stream and a
  controlled invalid-model request. Check failure and cancellation records too.

In the dashboard, check key identity, actual model, outcome, input/output tokens,
cache reads/writes and latency. Confirm `Credential: Client OAuth token` or
`used_client_oauth_token=true` for successful subscription requests. Inspect
records for credential-bearing headers or metadata.
If attribution is missing, stop and investigate before more traffic.

Dashboard cost is the API list-price equivalent, not the subscription invoice
or remaining quota. Verify the client's subscription status and account billing
settings, including paid extra usage. No server API key or fallback is configured,
but that alone does not disable paid extra usage in the subscription account.
Normalised Anthropic prompt tokens include cache reads and cache creation; do
not add those counters to prompt tokens again. Interrupted-stream counts may be
estimates, and cancellation may not immediately stop upstream generation.
LiteLLM records model requests, not complete tool-execution or parent/subagent
traces.

Traefik's response write timeout defaults to zero; its 180-second idle timeout
applies to idle keep-alive connections, not an active response. No shared ingress
timeouts are changed. LiteLLM's inference timeout is 1,800 seconds. The live
long-stream test must still pass through this listener and the intended client's
network.

## Pi compatibility

Pi 1.4.0's native `openai` provider uses subscription OAuth against
`https://api.openai.com/v1`, with scope `chatgpt.tokens.use.direct`. The
[LiteLLM Codex tutorial](https://docs.litellm.ai/docs/tutorials/openai_codex_byok)
describes legacy `openai-codex` and `/backend-api/codex`, and currently requires
v1.109.0, newer than the v1.106.6 stable release checked for this trial.
It does not establish support for native Pi tokens.

Pi also detects subscription request behaviour using an exact upstream URL
match. A base-URL override alone changes which request fields it sends. Stable
LiteLLM's `chatgpt/` provider obtains gateway-owned authentication, which would
change the agreed credential ownership. Do not use it as a substitute, change
providers, copy auth files or ask for another login to make this deployment pass.
Native Pi support remains a separate compatibility gate.

A follow-up source experiment found a candidate that preserves native Pi:
a small existing-provider extension can reuse Pi's built-in request builder and
SSE parser while redirecting only HTTP transport. Stable LiteLLM has a separate
Responses pass-through path with accounting support. Neither is enabled here.
Broad pass-through header forwarding can leak the gateway key upstream, and
source-helper tests do not prove credential safety, complete streaming or
persisted metrics. A disposable mock evaluation and a separately approved
dotfiles integration must precede any existing-login live test. Prefer a narrow
upstream header-filtering fix over maintaining a gateway fork.

## Operations and rollback

The proxy starts with a 1 GiB memory request and 3 GiB limit. LiteLLM's
production guide recommends about 4 GiB per database-connected worker; check
restarts and actual memory use before increasing traffic. PostgreSQL requests
256 MiB with a 512 MiB limit; the migration job has a 512 MiB request and 3 GiB
limit because `prisma_migration.py` imports the proxy CLI and runs Prisma's
schema/generator engines in-process. The worker's existing memory limits
already exceed its allocatable memory, so limits are not reserved capacity.

Check the shared worker filesystem and database size during the trial:

```sh
talosctl --nodes 192.168.4.133 mounts
kubectl -n litellm exec deployment/postgres -- \
  psql -U litellm -d litellm -c "SELECT pg_size_pretty(pg_database_size('litellm'));"
kubectl -n litellm exec deployment/postgres -- du -sh /var/lib/postgresql/data/pgdata
```

Investigate growth approaching 4 GiB or worker free space below 10 GB. Reduce
traffic or retention before the shared filesystem fills; that would also affect
Forgejo and Kubernetes. `max_wal_size` is a checkpoint target, not a hard disk
limit. These checks are manual; no monitoring platform is added.

For client rollback, remove only the LiteLLM URL and gateway header introduced
by the separate dotfiles change, restore the prior client settings, and confirm
a direct-provider streamed reply and tool cycle. Retain the existing local
subscription login. Native Pi remains direct throughout this initial trial.

To stop proxy traffic, revert the workload reconciliation in Git. Keep the
namespace, PV, claim and Talos directory; deletion is not a recovery method.
For application upgrades, inspect migration compatibility first. Reverting an
image does not undo schema migrations. Without a database backup, this trial
cannot promise database rollback after a destructive migration.

## Validation boundary

Local checks cover manifest rendering/schema validation and PostgreSQL
initialisation, authentication and restart persistence. Secret schema fixtures remove only the SOPS envelope and keep the
ciphertext; local checks do not decrypt them. Flux decryption remains a live
check. The database test uses PostgreSQL 17.11 processes, not the Kubernetes
container or Talos mount. Live Flux reconciliation, migrations,
readiness, DNS, gateway authentication, subscription
billing attribution, streaming/tool use, log privacy, retention cleanup and
client rollback require laptop/cluster access and remain acceptance gates.

## References

- [LiteLLM production deployment](https://docs.litellm.ai/docs/proxy/deploy)
- [LiteLLM v1.106.6 source](https://github.com/BerriAI/litellm/tree/v1.106.6)
- [PostgreSQL official image](https://hub.docker.com/_/postgres)
- [CloudNativePG storage](https://cloudnative-pg.io/docs/current/storage)
- [CloudNativePG backups](https://cloudnative-pg.io/docs/current/backup)
- [Traefik entrypoint timeouts](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/)

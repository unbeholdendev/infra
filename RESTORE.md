# Restoring vps-germany

The VPS is backed up by one thing: a nightly netcup snapshot of the whole
server, taken by `.forgejo/workflows/netcup-snapshot.yml` at 02:30. The four
newest are kept, so the window is about four days.

A snapshot is an image of the disk, so it covers everything on the box at once:
Dokploy's app definitions, Traefik's certificates, Stalwart and its mail,
listmonk and its Postgres, the sites.

Know what it is not:

- **Crash-consistent only.** Nothing is stopped or quiesced. It is the
  equivalent of pulling the plug, and the databases recover the way they would
  from a power cut. RocksDB and Postgres both have write-ahead logs and
  normally do, but normally is the word.
- **Not off-site.** Snapshots sit on netcup storage under the netcup account,
  which is the same account that holds the server they protect.
- **All or nothing.** There is no way to take back one mailbox or one database.
  A restore returns the whole machine to that moment.
- **Up to 24 hours old.** Anything since the last snapshot is gone.

## Setting it up

SCP has no scheduler, so the workflow drives netcup's REST API
(`https://www.servercontrolpanel.de/scp-core/api/v1`).

1. Log in once with the device flow and keep the refresh token:

   ```sh
   curl -s -X POST https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/auth/device \
     -d client_id=scp -d scope="openid offline_access"
   # open verification_uri_complete, approve, then:
   curl -s -X POST https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/token \
     -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
     -d client_id=scp -d device_code=<device_code>
   ```

2. Put `refresh_token` in the repo secret `NETCUP_REFRESH_TOKEN`. It never goes
   in the repo, and it is revocable from SCP without touching the password.
3. Find the server id and put it in the repo variable `NETCUP_SERVER_ID`:

   ```sh
   curl -s https://www.servercontrolpanel.de/scp-core/api/v1/servers \
     -H "Authorization: Bearer <access_token>" | jq
   ```

4. Check `runs-on` matches a label `deb-runner` registers, and that its image
   has `curl` and `jq`.

Scheduled workflows only fire from the default branch, so this does nothing
until it is merged to `main`.


## Checking it works

The workflow fails the run if the snapshot task does not reach `FINISHED`, and
it prunes nothing when that happens, so a red run in the list is the signal.
Beyond that, confirm the snapshots are real and fresh:

```sh
curl -s "https://www.servercontrolpanel.de/scp-core/api/v1/servers/$id/snapshots" \
  -H "Authorization: Bearer $token" | jq -r '.[] | "\(.creationTime) \(.name) \(.state)"'
```

Four entries, the newest from last night.

## Restoring

From SCP, or:

```
POST /api/v1/servers/{id}/snapshots/{name}/revert
```

This rolls the entire server back to that moment. Everything that happened
since is lost, for every service on the box, not only the one you are trying to
fix. Mail delivered since the snapshot is gone and senders will not retry,
because it was accepted at the time.

So before reverting for one service's sake, take a fresh snapshot of the
current state, or copy out what you need first. The revert is not reversible
unless you have that.

A revert has not been tested on this server. The first one will be a live
experiment, which is worth knowing in advance rather than at the time.

## Known gaps

- No copy exists outside netcup. Losing access to the netcup account loses the
  server and every snapshot with it.
- Nothing is stopped before a snapshot, so Stalwart's RocksDB is only
  crash-consistent. Stalwart's maintainer says to stop the server and copy
  `/var/lib/stalwart`. Branch `stalwart-backup-playbook` carries a playbook
  that does exactly that, nightly, pulled to TrueNAS with 30 days of ZFS
  snapshots. It is written and unapplied.

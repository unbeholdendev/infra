# infra

Ansible playbooks for the fleet, OpenTofu for VM provisioning, and backup jobs.

## Dion Talos VMs

[`opentofu/dion`](opentofu/dion/) defines one control-plane VM and one worker.
Run OpenTofu from the laptop; Talos setup stays manual. See its README for state,
credentials and the plan/apply workflow.

## Kubernetes

[`kubernetes`](kubernetes/) holds the Flux-managed homelab workloads, starting
with Homepage. See its README for reconciliation and local access commands.

## netcup snapshots

`.forgejo/workflows/netcup-snapshot.yml` snapshots the whole of `vps-germany`
at 02:30 and keeps the four newest. Snapshots sit on netcup storage under the
netcup account, are taken without stopping anything, and roll back the entire
server when reverted.

It needs, once:

- repo secret `NETCUP_REFRESH_TOKEN`, from the device flow:

  ```sh
  curl -s -X POST https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/auth/device \
    -d client_id=scp -d scope="openid offline_access"
  # open verification_uri_complete, approve, then:
  curl -s -X POST https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/token \
    -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
    -d client_id=scp -d device_code=<device_code>
  ```

- repo variable `NETCUP_SERVER_ID`, from
  `GET https://www.servercontrolpanel.de/scp-core/api/v1/servers`
- `heine` online, its `docker` label mapped to an image carrying `curl` and `jq`

Schedules only fire from the default branch, so it starts once merged.

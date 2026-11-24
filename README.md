# infra

Ansible playbooks for the fleet, OpenTofu for VM provisioning, and backup jobs.

This is a mirror of my private repo.

## Tools

`nix develop`, or direnv with nix-direnv, gives Ansible, OpenTofu, kubectl,
Flux, talosctl, sops and Helm.

## Dion VMs

[`opentofu/dion`](opentofu/dion/) defines two Talos VMs and the NixOS oren and heine VMs.
Run OpenTofu from the laptop; Talos setup stays manual. See its README for state,
credentials and the plan/apply workflow.

## Kubernetes

[`kubernetes`](kubernetes/) holds the Flux-managed homelab workloads, starting
with Homepage. See its README for reconciliation and local access commands.

## netcup snapshots

`.forgejo/workflows/netcup-snapshot.yml` snapshots the whole of `vps-germany`
weekly, Sunday 02:30, and keeps the four newest. Snapshots sit on netcup
storage under the netcup account, are taken without stopping anything, and roll
back the entire server when reverted.

netcup does not release the space a deleted snapshot held, so the disk's usage
in the netcup panel creeps up over time. When it does, run "storage
optimization" in the panel; it stops the server and deletes all snapshots.

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

# Monitoring

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
runs Prometheus, Grafana, kube-state-metrics and node-exporter. Grafana is at
`https://grafana.home.unbeholden.dev`, behind Traefik with the wildcard
certificate. Alertmanager is off: alert rules evaluate, but nothing is sent.

Prometheus keeps 15 days, capped at 5 GB, on a 6 GiB `local-path` claim on the
worker.

## Targets

- Kubernetes: API server, kubelets, CoreDNS, kube-state-metrics and both Talos
  nodes through node-exporter. Talos binds the controller manager, scheduler,
  etcd and kube-proxy metrics to localhost, so those scrapes are off.
- goddard (`192.168.4.11:9100`), heine (`192.168.4.16:9100`) and oren
  (`192.168.4.101:9100`) through node_exporter, as job `node-exporter`, so they
  appear in the "Node Exporter / Nodes" dashboard under their names. goddard's
  and heine's exporters are in `nixos/`; oren's is in dotfiles. All accept 9100
  only from the worker, `192.168.4.133`. If Prometheus moves to another node,
  add that node to each rule.

Every node-exporter target carries a `host` label naming the Proxmox host it
runs on: `dion` for the Talos nodes, oren and heine, `rune` for goddard. A new
target needs one too. The "Physical hosts" dashboard
(`dashboards/hosts.json`) sums CPU and memory by it.

node-exporter needs host network, PID namespace and paths, so it runs in its
own privileged `node-exporter` namespace; `monitoring` stays baseline.

## Grafana

Grafana reads its admin login from the Secret `grafana-admin` in `monitoring`,
with keys `admin-user` and `admin-password`, only when it first creates its
database; change the password in Grafana after that. Grafana's database sits on a 1 GiB `local-path` claim with
no backup. Put dashboards worth keeping in Git as ConfigMaps in `monitoring` labelled
`grafana_dashboard: "1"`. Grafana can read ConfigMaps and Secrets only in
`monitoring`, and kube-state-metrics does not collect Secrets, so neither can
read Secrets in other namespaces.

Claude and Codex sessions in this repo get Grafana's MCP server (`.mcp.json`,
`.codex/config.toml`). It reads a Viewer service account token from
`~/.config/grafana-mcp/token`, mode 600, on the machine the agent runs on.

## Before merging

1. Create `grafana-admin.sops.yaml` here: a Secret named `grafana-admin` in
   namespace `monitoring` with `admin-user` and `admin-password`, encrypted
   with `sops -e -i`. The kustomization lists it.
2. Deploy goddard (see [nixos](../../../nixos/README.md#deploy)) and oren with
   their node_exporter changes.

## Verify after merge

```sh
kubectl -n monitoring get helmrelease,pods,pvc
kubectl -n node-exporter get pods -o wide
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090
```

With the port forward running, <http://localhost:9090/targets> should show
every target up.

# SOPS secrets

SOPS encrypts Secret values in Git using age. The public recipient is in
`/.sops.yaml`; the private identity stays on the laptop, in Flux's bootstrap
Secret, and in an independent Vaultwarden backup. Kubernetes has no access to
Vaultwarden.

## Bootstrap before merging

Confirm the complete private identity file is backed up and recoverable without
this cluster. On the laptop, create the decryption Secret before merging the
Flux configuration:

```sh
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n flux-system create secret generic sops-age --from-file=age.agekey="$HOME/.config/sops/age/keys.txt"
kubectl --kubeconfig="$HOME/talos/dion-v2/kubeconfig" -n flux-system get secret sops-age
```

The first command reads the private file directly; it does not print its
contents or put them in shell history. If the Secret already exists, stop and
check its origin rather than replacing it. The `.agekey` entry suffix tells
Flux how to load the identity. Do not print the Secret as YAML or paste the key
into chat, Git, Nix configuration or command arguments.

The bootstrap Secret is deliberately not managed by SOPS: encrypting the only
key needed to decrypt itself would make recovery circular. Keep the existing
Flux SSH deploy-key Secret separate; it authenticates Git access, not decryption.

## Files and reconciliation

Name encrypted Kubernetes Secret manifests `*.sops.yaml` under `kubernetes/`.
The creation rule encrypts only `data` and `stringData`; resource names,
namespaces and other metadata remain visible. Base64 alone is not encryption.
Only put sensitive values in the encrypted fields.

Run `sops edit` from the infra checkout so it finds `.sops.yaml` and decrypted
values stay out of the tracked working file. The default local age identity is
`$HOME/.config/sops/age/keys.txt`. Include the encrypted manifest in its owning
Kustomization's resources, just like an ordinary Secret. Before staging, confirm
the file has SOPS metadata and encrypted values; review the diff without
printing decrypted content. Editor swap/backup files and plaintext exports also
need to stay out of Git.

The homelab root applies `spec.decryption` to every Flux Kustomization it
renders, including itself. They all reference `flux-system/sops-age`. Child
Kustomizations do not inherit decryption settings automatically; the root patch
provides them for current and future children declared there. A Kustomization
created outside that root needs its own configuration.

After merging, Flux discovers the change automatically:

```sh
nix shell nixpkgs#fluxcd --command flux get kustomizations --kubeconfig="$HOME/talos/dion-v2/kubeconfig"
```

All should become Ready. Spaceship credentials are the first encrypted workload;
the temporary staging Certificate tests live decryption and DNS-01 issuance.
See [certificate management](infrastructure/cert-manager/) for verification.

## Recovery

Restore the private identity from Vaultwarden, bootstrap Flux's Git access,
then recreate `sops-age` before expecting encrypted workloads to reconcile.
A missing key stops reconciliation, but existing workloads are not deleted
merely because decryption fails. Cluster administrators can read the deployed
key and decrypted Secrets; this is not isolation from cluster administrators.

Keep backups of Git and the identity independently. Changing the recipient in
`.sops.yaml` does not re-encrypt existing files: key rotation must also update
their recipients, and a compromised key requires rotating affected credentials.

## References

- [Flux SOPS decryption](https://fluxcd.io/flux/components/kustomize/kustomizations/#decryption)
- [SOPS age identities](https://getsops.io/docs/usage/identities/age/)
- [SOPS creation rules](https://getsops.io/docs/usage/identities/config-file/)

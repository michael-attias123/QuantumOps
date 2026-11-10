# ADR 0013 — Secrets from a shared Vault on its own VM, synced by External Secrets

- **Status:** Accepted
- **Date:** 2026-11-10
- **Supersedes:** the in-cluster Vault of ARCHITECTURE §12 (never built)
- **Relates to:** [ADR 0007](0007-zero-cost-policy.md), [ADR 0011](0011-tailnet-and-node-key-in-opentofu.md), [ADR 0012](0012-gitops-bootstrap.md)

## Context
The plan for P4 was a Vault inside the cluster, configured by vault-config-operator and auto-unsealed with a KMS key
in `infra/oci`. Other projects need a Vault too (house-manager, future ones), and a cluster rebuild shouldn't take the
secrets down with it. The 12 GB node is also tight: Vault and vault-config-operator would cost about 0.5 GB.

## Decision
- **One Vault for every project,** in the separate public repo
  [`shared-platform`](https://github.com/michael-attias123/shared-platform). It runs on its own Always Free
  `VM.Standard.E2.1.Micro`, at **https://vault.158-178-129-140.sslip.io**:
  - public HTTPS (Let's Encrypt), with OCI KMS auto-unseal and daily raft snapshots;
  - admin login with a password and TOTP; no root token.

  It's reached over the internet, not the tailnet, so GitHub Actions and other clusters can use it too.
- **Vault config lives in shared-platform,** one declaration per project: `projects/quantumops.yaml` declares
  QuantumOps' roles and secret paths. There's no vault-config-operator and no Vault CRs here.
- **The cluster logs in with its own service-account tokens:**
  - shared-platform registers this cluster's service-account public key (`stacks/vault-config/clusters/qops.pub.pem`)
    on the JWT mount `jwt-k8s-qops`;
  - ESO asks Kubernetes for a 10-minute token of its own service account, with audience `vault`, and logs in with
    it.

  Vault never needs to reach the k3s API, which stays tailnet-only, and the cluster holds no Vault credential.
- **External Secrets Operator** (wave 0) and one `ClusterSecretStore vault` (wave 1). Each secret is an
  `ExternalSecret`; the first is the Tailscale operator's OAuth client, from `kv/quantumops/tailscale`.
- **Seeding:** `make seed-secrets` copies values that QuantumOps' own OpenTofu state holds into Vault, through files
  and stdin, never on screen. `make bootstrap` no longer writes the OAuth Secret.
- **Shared ownership of the OCI basics:** shared-platform's `stacks/oci-foundation` owns the OpenTofu state bucket and
  the budget (imported, `prevent_destroy`). `make oci-bootstrap` only checks them. The KMS unseal key in
  `infra/oci/kms.tf` is no longer used but stays: it's free, and deleting a KMS vault can't be undone.
- **CI** also calls shared-platform's `security.yml@main` (gitleaks, actionlint, shellcheck). Building blocks are used
  at `main`, never at a tag (shared-platform `docs/contract.md`).
- **P11 note:** Alloy will send metrics, logs and traces to the shared Grafana stack, instead of in-cluster Grafana and
  Loki.

## Consequences
- A cluster rebuild doesn't touch the secrets. The Tailscale operator gets its credentials once ESO syncs, about a minute
  after Argo CD installs it.
- A new cluster needs its service-account key registered in shared-platform before ESO can log in. The key changes
  only when k3s' `service.key` does, that is on a full rebuild.
- If the Vault VM is down, existing Kubernetes Secrets stay as they are; only refreshes and new secrets wait.
- Later phases add their secrets to `projects/quantumops.yaml`: provider tokens in P7, the Kaggle key in P9, DB roles in
  P5. Per-level ServiceAccounts (`qops-l1`, `qops-l3`, `job-tracker`) become extra Kubernetes roles there, each with
  its own policy.
- Vault server operations (unseal, audit, snapshots, MFA) are documented and verified in shared-platform, not here.
- Node memory saved: about 0.5 GB that the in-cluster Vault and vault-config-operator would have used.

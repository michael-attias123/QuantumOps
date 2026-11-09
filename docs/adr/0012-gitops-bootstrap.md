# ADR 0012 — GitOps bootstrap: one Helm install, then Argo CD manages everything

- **Status:** Accepted
- **Date:** 2026-11-09
- **Relates to:** [ADR 0004](0004-git-manifest-trigger.md), [ADR 0008](0008-single-node-a1-cluster.md), [ADR 0011](0011-tailnet-and-node-key-in-opentofu.md)

## Context
P3 must install the platform from Git with one command, survive a cluster rebuild, deploy new images without
hand edits, and expose the Argo CD UI only on the tailnet. The node has 12 GB, so every component counts.

## Decision
- **Bootstrap:** `make bootstrap` is the only imperative step.
  1. Helm installs Argo CD **once**, from the same chart version and values file Git uses.
  2. It creates the Tailscale operator's OAuth Secret from OpenTofu output (P4 moves this to Vault).
  3. It applies one root Application.

  After that, Argo CD manages itself through the `argo-cd` Application. That Application never prunes, so a bad
  sync can't delete Argo CD.
- **App of apps as a small Helm chart** (`deploy/apps`). One values map lists every component: an upstream chart
  (multi-source with `$values` from this repo) or a path in the repo. Each has a sync wave (ARCHITECTURE §13).
  Environments are one values file each (`deploy/envs/oci`, `deploy/envs/ci`). There's no ApplicationSet
  controller, which saves a pod.
- **Access:** the Tailscale Kubernetes operator. Its OAuth client is created by OpenTofu (`tailscale_oauth_client`),
  so there's no manual step. The Argo CD UI is an Ingress of class `tailscale` (HTTPS with a ts.net certificate)
  in front of a ClusterIP service. No LoadBalancer, no NodePort, and no public ingress controller (Traefik is off).
- **Images:** `images.yml` builds on native amd64 and arm64 runners, publishes one multi-arch `sha-<short>` tag to
  GHCR, and the GitHub Actions bot commits that tag into `deploy/envs/oci/values.yaml`. Argo CD deploys it.
  Commits made with `GITHUB_TOKEN` don't trigger workflows, so this can't loop.
- **Branch protection as code** (`infra/github`):
  - `main` requires PRs and green CI.
  - Only the GitHub Actions app may bypass the rules, for those tag-bump commits.

## Consequences
- A rebuilt cluster comes back with `make infra-rebuild && make infra-apply && make kubeconfig && make bootstrap`.
- Argo CD's footprint is about 0.7 GB requested (no Dex, notifications or ApplicationSet; one replica each).
- The public repo carries no tailnet name: UI URLs are built from OpenTofu output at run time.
- The GHCR package must be public so the cluster can pull without credentials (a one-time setting; see the runbook).
- If a CI job is renamed, `infra/github` must change in the same PR, or PRs wait for a check that never runs.

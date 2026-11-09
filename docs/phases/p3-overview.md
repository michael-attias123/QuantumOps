# P3 overview — GitOps bootstrap

**Status:** done 2026-11-09 (`make verify-p3` passes).

## Goal
One command installs the whole platform from Git. After that the cluster follows `main`: changes, new images and
rebuilds need no manual `kubectl`.

## What was built
| Piece | Where |
|---|---|
| App of apps: one Application per component, with sync waves | [`deploy/apps/`](../../deploy/apps/) |
| Environments | [`deploy/envs/oci`](../../deploy/envs/oci/values.yaml) (real cluster), [`deploy/envs/ci`](../../deploy/envs/ci/values.yaml) (kind, P6) |
| Platform components | [`deploy/platform/`](../../deploy/platform/): namespaces, Argo CD values, Tailscale operator values, the Argo CD UI ingress |
| QuantumOps workloads | [`deploy/charts/qops`](../../deploy/charts/qops/): daily GHZ smoke CronJob |
| Bootstrap and checks | [`deploy/bootstrap/`](../../deploy/bootstrap/): root Application, `bootstrap.sh`, `check.sh`, `verify.sh` |
| Container image | [`packages/qops-runtime/Dockerfile`](../../packages/qops-runtime/Dockerfile), [`images.yml`](../../.github/workflows/images.yml) |
| Branch protection | [`infra/github/`](../../infra/github/) |
| Operator OAuth client | `tailscale_oauth_client` in [`infra/oci/tailscale.tf`](../../infra/oci/tailscale.tf) |
| Make targets | [`make/deploy.mk`](../../make/deploy.mk), `github-*` in [`make/infra.mk`](../../make/infra.mk), `verify-p3` |
| Decision, runbook | [ADR 0012](../adr/0012-gitops-bootstrap.md), [GitOps runbook](../runbooks/gitops.md) |

In the cluster:

| Wave | Application | What |
|---|---|---|
| −2 | `namespaces` | `argocd` (PSA baseline), `tailscale` (privileged, for the proxies), `qops` (restricted) |
| −1 | `argo-cd` | Argo CD chart 10.17.1 (v3.6.1) managing itself; never prunes |
| 0 | `tailscale-operator` | chart 1.104.4; joins the tailnet as `tag:k8s-operator` |
| 1 | `argocd-access` | Ingress of class `tailscale` → `https://argocd.<tailnet>.ts.net` |
| 2 | `qops` | `qops-smoke` CronJob, image `ghcr.io/michael-attias123/qops-runtime` |

Memory after bootstrap: 1.9 GiB used of 11 GiB on the node. Argo CD uses about 0.2 GiB, and the operator and its
proxy about 35 MiB.

## How to use it
```bash
make argocd-status     # sync/health of every app
make argocd-password   # admin password -> clipboard; UI at https://argocd.<tailnet>.ts.net
make deploy-check      # validate deploy/ before a PR (same as CI)
make bootstrap         # after a cluster rebuild; safe to rerun
make verify-p3         # phase checks
```
To change the cluster: edit `deploy/`, open a PR, merge. To ship code: merge a change under `packages/` or
`research/algorithms/`. CI builds the image and commits the new tag, and Argo CD rolls it out.

## Definition of Done — evidence
| Check | Result |
|---|---|
| `make bootstrap` → all apps Synced/Healthy, no manual kubectl | ✅ 6/6 Synced + Healthy about 4 minutes after the Helm install (on the P2 cluster, first install) |
| A Git change to a value shows up in the cluster | ✅ the tag commit `243d9a7` changed `deploy/envs/oci/values.yaml`, and the CronJob followed (`sha-c5a1979`) |
| An image built on `main` is bumped and deployed automatically | ✅ `images` run on `c5a1979`: amd64 + arm64 builds, manifest `sha-c5a1979`, tag commit; then `verify-p3` ran the smoke job on that image |
| Argo CD UI from any tailnet computer, nowhere else | ✅ `https://argocd.tailda90a2.ts.net/healthz` → ok from the tailnet; no LoadBalancer or NodePort services; the node has no inbound rules (P2) |
| Branch protection | ✅ `main` ruleset: PRs, 7 required checks, no force-push or deletion; only the tag-bump deploy key bypasses it |

## What went wrong and how it was fixed
- **The ruleset couldn't exempt the GitHub Actions app.** On a personal account GitHub answers 422. The bump job now
  pushes with a deploy key that `infra/github` creates (key, deploy key, Actions secret), and deploy keys bypass.
- **yamllint and `check-yaml` tried to parse Helm templates.** They now skip `deploy/**/templates/`;
  `make deploy-check` renders the templates and validates the result instead.
- **Editing through the Windows path dropped the executable bit** on two scripts. Fixed before the PR.
- **The GHCR package wasn't private, contrary to the plan.** It inherited the public repo's visibility; an anonymous
  pull returns 200, so no manual step was needed.

## Decisions
[ADR 0012](../adr/0012-gitops-bootstrap.md): one Helm install, then Argo CD manages everything; the app of apps is a
small Helm chart without an ApplicationSet controller; the UI is reached through the Tailscale operator; image tags are
bumped by a commit to Git.

## Limitations
- The Tailscale operator's OAuth secret is copied in by `make bootstrap`. P4 moves it to Vault and External Secrets.
- The Argo CD admin password is the generated initial one; there's no SSO (single user).
- The "freshly rebuilt cluster" check ran on the P2 cluster's first install, not after `make infra-rebuild`. The
  rebuild path is the same script.

## Next: P4 — Vault + External Secrets
Vault with OCI KMS auto-unseal (the key from P2), External Secrets Operator, and the operator OAuth secret moved out of
`make bootstrap`.

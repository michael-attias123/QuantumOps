# Runbook — GitOps (P3)

Argo CD runs in the cluster and keeps it equal to `deploy/` on `main`. Commands run from the repo root on the
admin computer (WSL on Windows). The Argo CD UI is at `https://argocd.<tailnet>.ts.net`; any computer on your
tailnet can open it.

## Everyday
| Task | How |
|---|---|
| Change something in the cluster | Edit files under `deploy/`, open a PR, merge. Argo CD syncs within ~3 minutes |
| See sync and health | `make argocd-status`, or the UI |
| Log in to the UI | user `admin`, password: `make argocd-password` (copies it to the clipboard) |
| Check manifests before a PR | `make deploy-check` (same as CI) |
| Phase checks | `make verify-p3` |

## How a new image reaches the cluster
1. A PR changes `packages/`, `research/algorithms/` or the lock file. `images.yml` builds both architectures and
   runs the GHZ smoke test, without publishing.
2. After the merge, `images.yml` on `main` publishes `ghcr.io/michael-attias123/qops-runtime:sha-<short>`.
   The bot then commits that tag to `deploy/envs/oci/values.yaml`.
3. Argo CD sees the commit and updates the `qops-smoke` CronJob.

**One-time setting:** a new GHCR package starts private. After the first image is published, open
github.com → your profile → *Packages* → `qops-runtime` → *Package settings* → *Change visibility* → **Public**.
Otherwise pods fail with `ErrImagePull`.

## Fresh or rebuilt cluster
```bash
make infra-rebuild   # only when rebuilding; review the plan
make infra-apply
make kubeconfig      # after ~5 minutes of first boot
make bootstrap
```
`make bootstrap` is safe to rerun. It skips the Helm install when Argo CD is already there.

## Problems
**An Application is `OutOfSync` or `Degraded`.** `make argocd-status`, then open it in the UI to see which resource
and why. Most often a value is wrong in Git: fix it with a PR. To force a sync from the UI, use *Sync*.

**The UI doesn't open.** Check the `argocd` device on the
[Tailscale machines page](https://login.tailscale.com/admin/machines). The operator creates it a minute after the
`argocd-access` Application syncs. Then check `kubectl -n tailscale get pods`. If the operator logs show OAuth
errors, rerun `make bootstrap` (it rewrites the `operator-oauth` Secret from OpenTofu output).

**Pods show `ErrImagePull` for `qops-runtime`.** The package is still private (see above), or the tag in
`deploy/envs/oci/values.yaml` was never published. Check the latest `images` workflow run.

**The bot can't push the tag bump.** The `main` ruleset must list the GitHub Actions app as a bypass actor
(`infra/github/main.tf`). Run `make github-plan` and check that the plan shows no changes.

**Argo CD itself is broken.** Its Application never prunes. Reinstall with Helm by deleting the `argocd-server`
deployment and rerunning `make bootstrap`: Argo CD's own resources are recreated and the Applications remain.

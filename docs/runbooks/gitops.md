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
| Phase checks | `make verify-p3`, `make verify-p4` |
| See secret sync | `make secrets-status` |
| Re-read Vault now | `make secrets-sync` (otherwise ESO refreshes every hour) |

## How a new image reaches the cluster
1. A PR changes `packages/`, `research/algorithms/` or the lock file. `images.yml` builds both architectures and
   runs the GHZ smoke test, without publishing.
2. After the merge, `images.yml` on `main` publishes `ghcr.io/michael-attias123/qops-runtime:sha-<short>`.
   The bot then commits that tag to `deploy/envs/oci/values.yaml`.
3. Argo CD sees the commit and updates the `qops-smoke` CronJob.

The package is public: it inherited the visibility of the public repository (checked on 2026-11-09 with an
anonymous pull). If pods ever fail with `ErrImagePull`, check github.com → *Packages* → `qops-runtime` →
*Package settings* → visibility **Public**.

## Secrets (P4)
Secrets live in the shared Vault (shared-platform, [ADR 0013](../adr/0013-shared-vault.md)). ESO copies them into
Kubernetes Secrets. To put QuantumOps' own values into Vault (safe to rerun; nothing is shown):
```bash
cd ~/shared-platform && make vault-login   # password + 6-digit code
cd ~/QuantumOps && make seed-secrets && make secrets-sync
```
To add a new secret:
1. Add its path and keys to `projects/quantumops.yaml` in shared-platform (PR).
2. Write the value with `make vault-seed PROJECT=quantumops` there.
3. Add an `ExternalSecret` under `deploy/` here (PR).

## Fresh or rebuilt cluster
```bash
make infra-rebuild   # only when rebuilding; review the plan
make infra-apply
make kubeconfig      # after ~5 minutes of first boot
make bootstrap
```
`make bootstrap` is safe to rerun. It skips the Helm install when Argo CD is already there.

**After a full rebuild,** k3s has a new service-account key, so ESO can't log in to Vault until shared-platform
knows it. Copy the new key into `stacks/vault-config/clusters/qops.pub.pem` there (PR, then apply):
```bash
bash infra/scripts/node.sh ssh sudo openssl rsa -in /var/lib/rancher/k3s/server/tls/service.key -pubout
```

## Problems
**An Application is `OutOfSync` or `Degraded`.** `make argocd-status`, then open it in the UI to see which resource
and why. Most often a value is wrong in Git: fix it with a PR. To force a sync from the UI, use *Sync*.

**The browser shows `ERR_TUNNEL_CONNECTION_FAILED` (Windows behind a company proxy).** The browser sends
`*.ts.net` to the company proxy, which can't reach your tailnet. Add an exception: *Settings → Network & internet →
Proxy → Use a proxy server → Edit*, and append `*.ts.net;100.*` to the exceptions list. If your company locks that
setting, use a browser with its own proxy settings (Firefox: *Settings → Network Settings → No proxy for*:
`.ts.net, 100.64.0.0/10`). The `make` targets already bypass the proxy for the tailnet.

**The UI doesn't open.** Check the `argocd` device on the
[Tailscale machines page](https://login.tailscale.com/admin/machines). The operator creates it a minute after the
`argocd-access` Application syncs. Then check `kubectl -n tailscale get pods`. If the operator logs show OAuth
errors, check the Secret's source: `make secrets-status`. Then `make seed-secrets && make secrets-sync`
(after `make vault-login` in shared-platform).

**Pods show `ErrImagePull` for `qops-runtime`.** The package is still private (see above), or the tag in
`deploy/envs/oci/values.yaml` was never published. Check the latest `images` workflow run.

**The bump job can't push the tag.** It pushes with the `IMAGE_BUMP_DEPLOY_KEY` deploy key, which the `main`
ruleset lets bypass. Run `make github-plan`: it should show no changes. If the key or secret was deleted on
GitHub, the plan recreates them; apply it.

**Argo CD itself is broken.** Its Application never prunes. Reinstall with Helm by deleting the `argocd-server`
deployment and rerunning `make bootstrap`: Argo CD's own resources are recreated and the Applications remain.

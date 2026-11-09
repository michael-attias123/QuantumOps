# Runbook — OCI cluster (P2)

The cluster is one Oracle Cloud Always Free A1 VM (2 OCPU / 12 GB) running single-node k3s, reachable only over
Tailscale. Code: [`infra/oci/`](../../infra/oci/). Commands run on the **admin computer** (WSL2 on Windows), from the
repo root. Secrets live only in `~/.config/qops/*.env` and `~/.oci/`.

## Everyday
| Task | Command |
|---|---|
| See what would change | `make infra-plan` |
| Apply the reviewed plan | `make infra-apply` |
| Get kubectl access (any computer on the tailnet) | `make kubeconfig`, then `kubectl get nodes` |
| Shell on the node | `make ssh-server` |
| First-boot progress | `make node-status` |
| Node IP, KMS IDs | `make infra-output` |
| Offline checks (what CI runs) | `make infra-check` |
| Phase checks against the live cluster | `make verify-p2` |
| Install the platform from Git (after a rebuild) | `make bootstrap` ([GitOps runbook](gitops.md)) |

Other computers need only Tailscale, kubectl, git and make: `make kubeconfig` copies the kubeconfig over Tailscale SSH.

## First apply
1. `make infra-plan`. Expect **14 to add**. Check the node is `VM.Standard.A1.Flex 2 OCPU / 12 GB`.
2. `make infra-apply`. It takes 2–5 minutes. **This replaces the Tailscale policy file** with the one in
   `infra/oci/tailscale.tf`.
3. Wait about 5 minutes for first boot, then `make node-status` until it shows `qops bootstrap done`.
4. `make kubeconfig`, then `make verify-p2`.

## Problems
**`Out of host capacity` on apply.** Free A1 capacity is sometimes exhausted. Your region has one availability
domain, so wait and retry `make infra-plan && make infra-apply` later (early morning often works).
Nothing is created halfway that costs money.

**The node never shows up on the tailnet.** The auth key is single-use and expires one hour after the plan was
applied. If first boot failed or was slow, rebuild: `make infra-rebuild`, then `make infra-apply`. To read the boot
log without Tailscale: OCI console → Compute → Instances → `qops-node-1` → *Console connection* (uses
`~/.ssh/qops_oci`).

**kubectl says `Forbidden` (behind a company proxy).** The proxy gets the request for the node's 100.x address.
The `make` targets already bypass it. For plain `kubectl`, add this line to `~/.bashrc` and open a new shell:
```bash
export NO_PROXY="100.64.0.0/10,.ts.net${NO_PROXY:+,$NO_PROXY}" no_proxy="100.64.0.0/10,.ts.net${no_proxy:+,$no_proxy}"
```

**`make kubeconfig` can't connect from WSL.** Check `tailscale.exe status` on Windows shows `qops-node-1`. WSL2 reaches
the tailnet through Windows; if it doesn't, enable mirrored networking in `%UserProfile%\.wslconfig`
(`[wsl2]` `networkingMode=mirrored`), then `wsl --shutdown`.

**Idle reclaim.** Oracle may reclaim Always Free VMs that stay almost idle for 7 days (CPU, network and memory all
below 20%). From P3 on, the platform components keep the node busy enough. If it happens, the VM is stopped, not
deleted: start it from the console, or rebuild.

**Lost `~/.config/qops/tofu.env` (state passphrase).** The state can't be decrypted. The cluster keeps running.
Restore the passphrase from your password manager. If it's truly gone, delete the state object in the bucket and
import or recreate the resources (ask before doing this).

## Rebuild from scratch
`make infra-rebuild` → review → `make infra-apply`. This replaces the node and its Tailscale key. Everything else
(network, KMS key) stays. Afterwards, delete the old `qops-node-1` from the
[Tailscale machines page](https://login.tailscale.com/admin/machines) (the new one may be `qops-node-1-1` until then),
and run `make kubeconfig` again. From P3, Argo CD restores the workloads from Git; from P4, Vault data comes back from
snapshots.

## Removing everything
`make infra-destroy`. The KMS key and vault enter a pending-deletion period (at least 7 days) instead of vanishing.
The Tailscale policy stays as it is.

## Trial safety (ADR 0010)
- `infra/oci/variables.tf` refuses more than 2 OCPU / 12 GB for the node.
- Don't create A1 machines by hand: more than 2 OCPU / 12 GB in total when the trial ends (2026-12-08) gets **all** A1
  VMs disabled and deleted.

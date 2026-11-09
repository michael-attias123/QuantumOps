# P2 overview — Cloud cluster (OCI Always Free + Tailscale)

**Status:** cluster running since 2026-11-09. Two DoD items are still open (see the end).

## Goal
An always-on, private, $0 Kubernetes cluster that every computer can reach, with no public ports.

## What was built
| Piece | Where |
|---|---|
| One OpenTofu stack for Oracle Cloud and Tailscale | [`infra/oci/`](../../infra/oci/) |
| Wrappers that supply credentials from `~/.config/qops/` | [`infra/scripts/tofu.sh`](../../infra/scripts/tofu.sh), [`node.sh`](../../infra/scripts/node.sh) |
| Make targets | [`make/infra.mk`](../../make/infra.mk), `verify-p2` in [`make/verify.mk`](../../make/verify.mk) |
| Offline tests (mocked providers, in CI) | [`infra/oci/tests/plan.tftest.hcl`](../../infra/oci/tests/plan.tftest.hcl) |
| Runbook | [`docs/runbooks/oci-cluster.md`](../runbooks/oci-cluster.md) |
| Decision | [ADR 0011](../adr/0011-tailnet-and-node-key-in-opentofu.md): tailnet policy and node key in OpenTofu |
| Setup scripts used before P2 | [`infra/bootstrap/`](../../infra/bootstrap/), guide [p2-prerequisites](p2-prerequisites.md) |

What runs in the cloud, all inside the `qops` compartment in `il-jerusalem-1`:
- **`qops-node-1`:** `VM.Standard.A1.Flex`, 2 OCPU / 12 GB, 100 GB disk, Ubuntu 24.04 arm64. Exactly the Always
  Free allowance; the code refuses more.
- **k3s v1.37.2, single node.** It runs on the tailnet IP (`--flannel-iface tailscale0`) with Traefik and servicelb
  off, and the node is labelled `qops.io/pool=cpu`. After boot: about 1.1 GiB of 11 GiB memory used.
- **Network:** VCN `10.20.0.0/16`. The node's security list allows **no inbound traffic**, only outbound; the VCN's
  default list is emptied too.
- **Tailscale:** the tailnet policy and MagicDNS come from Git. The node joined with a single-use 1-hour key as
  `tag:qops-node`, and you reach it with Tailscale SSH (no SSH keys).
- **KMS:** a vault and an HSM key for Vault auto-unseal in P4, and a policy that lets only the node use only that key.
- **State:** in the `qops-tofu-state` bucket, encrypted.

## How to use it
On the admin computer (WSL Ubuntu), from `~/QuantumOps`:
```bash
make kubeconfig        # kubectl context "qops"
kubectl get nodes
make ssh-server        # shell on the node
make infra-plan        # any infra change: plan, review...
make infra-apply       # ...then apply exactly that plan
make verify-p2         # phase checks
```
Behind the company proxy, plain `kubectl` needs the tailnet excluded from the proxy. The `make` targets do this
themselves; for your shell, add the `NO_PROXY` line from the runbook to `~/.bashrc`.

## Definition of Done — evidence
| Check | Result |
|---|---|
| `make kubeconfig && kubectl get nodes` → 1 Ready arm64 node | ✅ `qops-node-1 Ready control-plane v1.37.2+k3s1`, arm64, from the admin computer. **Second computer: open** |
| Public IP answers on no port | ✅ OCI shows the subnet's only security list with **0 ingress rules**, no NSGs; ports 22/80/443/6443/10250 closed from outside the tailnet |
| `tofu plan` shows no drift | **Open:** 3 resources still to add (KMS key, its policy, emptied default list) — see below |
| OCI cost report shows $0 | **Open:** check *Billing → Cost Analysis* after a day |
| Offline checks in CI | ✅ `opentofu (infra/oci)`: fmt, validate, 8 tests |

## What went wrong and how it was fixed
- **KMS key: "Service Unavailable"** on the first apply. A new vault's endpoint takes a few minutes to start; the retry
  plan contains just the key and its policy.
- **`make kubeconfig` asked for a username.** k3s writes `- name: default` for the user, which the rename missed.
  Fixed in `node.sh`.
- **kubectl got "Forbidden".** The company proxy got the request for the node's 100.x address. The scripts now always
  exclude `100.64.0.0/10` and `.ts.net` from the proxy.
- **The VCN default security list allows SSH from anywhere.** It was unused, but it's now managed and emptied.

## Decisions
- One node, the whole A1 allowance ([ADR 0008](../adr/0008-single-node-a1-cluster.md)).
- Trial credits: the GPU test (track T) is dropped, because trial tenancies can't request a GPU limit
  ([ADR 0010](../adr/0010-oci-trial-burst-layer.md)).
- Tailscale managed by OpenTofu, with no hand-made auth keys ([ADR 0011](../adr/0011-tailnet-and-node-key-in-opentofu.md)).

## Limitations
- No node redundancy: a reboot is a short outage. Rebuilding is `make infra-rebuild`.
- Oracle may reclaim an almost idle Always Free VM after 7 days; from P3 the platform keeps it busy.
- The Tailscale API token expires after 90 days (renew with `make tailscale-login`).

## Next: P3 — GitOps bootstrap
Argo CD installed from Git, the Tailscale Kubernetes operator, and Argo CD's UI at `argocd.<tailnet>.ts.net`.

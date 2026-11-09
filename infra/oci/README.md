# infra/oci — the cloud cluster (P2)

One OpenTofu stack for everything QuantumOps needs on Oracle Cloud Always Free and Tailscale. Run it with `make`
(see the [runbook](../../docs/runbooks/oci-cluster.md)); don't call `tofu` directly, because
[`infra/scripts/tofu.sh`](../scripts/tofu.sh) supplies the credentials and backend settings from `~/.config/qops/`.

| File | What |
|---|---|
| `versions.tf` | Provider pins, S3 backend in the `qops-tofu-state` bucket, state and plan encryption |
| `variables.tf` | Inputs, including the Always Free guard: node ≤ 2 OCPU / 12 GB, boot volume ≤ 200 GB |
| `main.tf` | Providers, the `qops` compartment, image and availability-domain lookups |
| `network.tf` | VCN, internet gateway, route table, security list with **no inbound rules**, subnet |
| `node.tf` | The A1 VM (k3s server) |
| `templates/cloud-init.yaml.tftpl` | First boot: Tailscale join (tagged, Tailscale SSH), single-node k3s on `tailscale0` |
| `kms.tf` | Vault + HSM key for HashiCorp Vault auto-unseal (P4), dynamic group and policy for the node |
| `tailscale.tf` | Tailnet policy, MagicDNS, the node's single-use auth key ([ADR 0011](../../docs/adr/0011-tailnet-and-node-key-in-opentofu.md)) |
| `outputs.tf` | Node name, tailnet name, public IP, KMS IDs for P4 |
| `tests/plan.tftest.hcl` | Offline tests with mocked providers (`make infra-check`, runs in CI) |

The k3s node settings follow [ADR 0008](../../docs/adr/0008-single-node-a1-cluster.md): Traefik and servicelb are
disabled (the Tailscale operator exposes services from P3), the node is labelled `qops.io/pool=cpu`, and the API
server listens on the node's tailnet IP.

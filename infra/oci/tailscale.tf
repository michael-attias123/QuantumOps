# The tailnet policy is managed from Git. Applying this REPLACES the policy file in the Tailscale admin console.

locals {
  tailnet_policy = {
    tagOwners = {
      "tag:qops-node"    = ["autogroup:admin"]  # cluster VMs (P2)
      "tag:k8s-operator" = []                   # Tailscale Kubernetes operator (P3)
      "tag:k8s"          = ["tag:k8s-operator"] # services the operator exposes (P3)
    }
    grants = [
      # Your own devices can reach everything on the tailnet.
      { src = ["autogroup:member"], dst = ["*"], ip = ["*"] },
      # Tagged infrastructure can reach other tagged infrastructure, but not your personal devices.
      { src = ["tag:qops-node", "tag:k8s-operator", "tag:k8s"], dst = ["tag:qops-node", "tag:k8s-operator", "tag:k8s"], ip = ["*"] },
    ]
    ssh = [
      # Tailscale SSH into the nodes as 'ubuntu' (which has sudo); no SSH keys needed.
      { action = "accept", src = ["autogroup:member"], dst = ["tag:qops-node"], users = ["ubuntu"] },
      # Tailscale's default: SSH between your own devices, with a periodic browser check.
      { action = "check", src = ["autogroup:member"], dst = ["autogroup:self"], users = ["autogroup:nonroot", "root"] },
    ]
  }
}

resource "tailscale_acl" "this" {
  acl                        = jsonencode(local.tailnet_policy)
  overwrite_existing_content = true
}

resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}

# Single-use, pre-approved, tagged key that the node uses once, at first boot. It expires after an hour.
# A used or expired key stays in state without causing drift ("never"); `make infra-rebuild` replaces the
# key together with the node, so a rebuilt node always gets a fresh one.
resource "tailscale_tailnet_key" "node" {
  description         = "qops node first boot"
  reusable            = false
  ephemeral           = false
  preauthorized       = true
  expiry              = 3600
  tags                = ["tag:qops-node"]
  recreate_if_invalid = "never"

  depends_on = [tailscale_acl.this]
}

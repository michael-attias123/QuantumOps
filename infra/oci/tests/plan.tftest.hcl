# Offline checks with mocked providers: no OCI or Tailscale credentials needed (runs in CI).
#   tofu -chdir=infra/oci test

mock_provider "oci" {}

mock_provider "tailscale" {
  mock_resource "tailscale_tailnet_key" {
    defaults = {
      key = "tskey-auth-test-not-a-real-key" # gitleaks:allow (fake, for tests)
    }
  }
}

variables {
  region           = "test-region-1"
  tenancy_ocid     = "ocid1.tenancy.oc1..test"
  state_passphrase = "test-passphrase-not-secret"
  ssh_public_key   = "ssh-ed25519 AAAATEST qops-oci"
  tailnet_dns_name = "tail1234.ts.net"
  # Mocked data sources return empty lists, so pin what the real lookups would find.
  image_ocid          = "ocid1.image.oc1..test"
  availability_domain = "Abcd:TEST-REGION-1-AD-1"
}

run "defaults_fit_always_free" {
  command = apply

  assert {
    condition     = oci_core_instance.node.shape == "VM.Standard.A1.Flex"
    error_message = "The node must be an Ampere A1 Flex VM."
  }
  assert {
    condition     = oci_core_instance.node.shape_config[0].ocpus == 2 && oci_core_instance.node.shape_config[0].memory_in_gbs == 12
    error_message = "The default node must use exactly the Always Free A1 allowance (2 OCPU / 12 GB)."
  }
  assert {
    condition     = oci_core_instance.node.source_details[0].boot_volume_size_in_gbs <= 200
    error_message = "The boot volume must fit the 200 GB Always Free block storage."
  }
}

run "no_public_inbound" {
  command = apply

  assert {
    condition     = length(oci_core_security_list.node.ingress_security_rules) == 0
    error_message = "The node security list must have no inbound rules."
  }
  assert {
    condition     = length(oci_core_default_security_list.default.ingress_security_rules) == 0 && length(oci_core_default_security_list.default.egress_security_rules) == 0
    error_message = "The VCN's default security list must be emptied (it allows SSH from anywhere by default)."
  }
  assert {
    condition     = one(oci_core_security_list.node.egress_security_rules).destination == "0.0.0.0/0"
    error_message = "The node needs outbound internet."
  }
}

run "tailscale_key_is_short_lived_and_tagged" {
  command = apply

  assert {
    condition     = tailscale_tailnet_key.node.expiry == 3600 && !tailscale_tailnet_key.node.reusable
    error_message = "The node auth key must be single-use and expire within an hour."
  }
  assert {
    condition     = tailscale_tailnet_key.node.preauthorized && length(tailscale_tailnet_key.node.tags) == 1 && contains(tailscale_tailnet_key.node.tags, "tag:qops-node")
    error_message = "The node auth key must be pre-approved and tagged tag:qops-node."
  }
  assert {
    condition     = contains(keys(jsondecode(tailscale_acl.this.acl).tagOwners), "tag:qops-node")
    error_message = "The tailnet policy must define tag:qops-node."
  }
  assert {
    condition     = length(tailscale_oauth_client.k8s_operator.tags) == 1 && contains(tailscale_oauth_client.k8s_operator.tags, "tag:k8s-operator")
    error_message = "The operator OAuth client must be tagged tag:k8s-operator only."
  }
}

run "cloud_init_installs_k3s_on_the_tailnet" {
  command = apply

  assert {
    condition = alltrue([
      for s in [
        "--advertise-tags tag:qops-node",
        "--flannel-iface tailscale0",
        "--disable traefik",
        "--disable servicelb",
        "--node-label qops.io/pool=cpu",
        "--tls-san \"qops-node-1.tail1234.ts.net\"",
        "tskey-auth-test-not-a-real-key",
      ] : strcontains(base64decode(oci_core_instance.node.metadata["user_data"]), s)
    ])
    error_message = "cloud-init must join Tailscale with the tag and install k3s bound to tailscale0."
  }
}

run "rejects_more_ocpus_than_always_free" {
  command = plan
  variables {
    node_ocpus = 4
  }
  expect_failures = [var.node_ocpus]
}

run "rejects_more_memory_than_always_free" {
  command = plan
  variables {
    node_memory_gb = 24
  }
  expect_failures = [var.node_memory_gb]
}

run "rejects_a_short_state_passphrase" {
  command = plan
  variables {
    state_passphrase = "short"
  }
  expect_failures = [var.state_passphrase]
}

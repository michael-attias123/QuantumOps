# The whole cluster: one Always Free A1 VM running single-node k3s (ADR 0008).

resource "oci_core_instance" "node" {
  compartment_id      = oci_identity_compartment.qops.id
  availability_domain = local.availability_domain
  display_name        = var.node_name
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = merge(local.tags, { "qops-role" = "k3s-server" })

  shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true # outbound internet only; the security list allows no inbound traffic
    hostname_label   = var.node_name
  }

  metadata = {
    ssh_authorized_keys = trimspace(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      hostname           = var.node_name
      tailscale_auth_key = tailscale_tailnet_key.node.key
      tailnet_dns_name   = var.tailnet_dns_name
      k3s_channel        = var.k3s_channel
    }))
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false
  }

  lifecycle {
    # Don't rebuild the node when Canonical publishes a newer image or a fresh (unused) auth key is minted.
    # To rebuild on purpose: make infra-rebuild.
    ignore_changes = [
      source_details[0].source_id,
      metadata["user_data"],
    ]
  }
}

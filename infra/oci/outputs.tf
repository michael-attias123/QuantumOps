output "node_name" {
  description = "Hostname of the node in OCI and on the tailnet."
  value       = var.node_name
}

output "node_tailnet_fqdn" {
  description = "MagicDNS name of the node."
  value       = "${var.node_name}.${var.tailnet_dns_name}"
}

output "node_public_ip" {
  description = "Public IP (outbound only; must answer on no port)."
  value       = oci_core_instance.node.public_ip
}

output "node_shape" {
  description = "Shape and size of the node."
  value       = "${oci_core_instance.node.shape} ${var.node_ocpus} OCPU / ${var.node_memory_gb} GB"
}

output "compartment_id" {
  description = "Compartment holding every QuantumOps resource."
  value       = oci_identity_compartment.qops.id
}

output "kms_vault_unseal" {
  description = "What P4's HashiCorp Vault needs for OCI KMS auto-unseal."
  value = {
    key_id              = oci_kms_key.vault_unseal.id
    crypto_endpoint     = oci_kms_vault.qops.crypto_endpoint
    management_endpoint = oci_kms_vault.qops.management_endpoint
  }
}

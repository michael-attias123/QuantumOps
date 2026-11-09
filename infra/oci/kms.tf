# Key for HashiCorp Vault auto-unseal (P4). Always Free includes 20 HSM key versions in a virtual vault.
# The node reaches it with instance-principal auth, so no API key ever goes onto the VM.

resource "oci_kms_vault" "qops" {
  compartment_id = oci_identity_compartment.qops.id
  display_name   = "qops-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = local.tags
}

resource "oci_kms_key" "vault_unseal" {
  compartment_id      = oci_identity_compartment.qops.id
  display_name        = "qops-vault-unseal"
  management_endpoint = oci_kms_vault.qops.management_endpoint
  protection_mode     = "HSM"
  freeform_tags       = local.tags

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

resource "oci_identity_dynamic_group" "node" {
  compartment_id = var.tenancy_ocid
  name           = "qops-node"
  description    = "QuantumOps cluster nodes (instances in the qops compartment)"
  matching_rule  = "ALL {instance.compartment.id = '${oci_identity_compartment.qops.id}'}"
  freeform_tags  = local.tags
}

resource "oci_identity_policy" "node_kms" {
  compartment_id = oci_identity_compartment.qops.id
  name           = "qops-node-kms"
  description    = "Let cluster nodes use only the Vault unseal key"
  freeform_tags  = local.tags
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.node.name} to use vaults in compartment ${oci_identity_compartment.qops.name}",
    "Allow dynamic-group ${oci_identity_dynamic_group.node.name} to use keys in compartment ${oci_identity_compartment.qops.name} where target.key.id = '${oci_kms_key.vault_unseal.id}'",
  ]
}

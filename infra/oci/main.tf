provider "oci" {
  region              = var.region
  config_file_profile = var.oci_profile
}

# Authenticates with TAILSCALE_API_KEY from ~/.config/qops/tailscale.env; tailnet "-" is the token's own tailnet.
provider "tailscale" {}

locals {
  tags = {
    "qops-managed-by" = "opentofu"
    "qops-stack"      = "infra/oci"
  }
}

# Everything QuantumOps creates lives in its own compartment, so it's easy to find, audit and delete.
resource "oci_identity_compartment" "qops" {
  compartment_id = var.tenancy_ocid
  name           = "qops"
  description    = "QuantumOps platform (managed by OpenTofu, infra/oci)"
  enable_delete  = true
  freeform_tags  = local.tags
}

data "oci_identity_availability_domains" "all" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

locals {
  availability_domain = coalesce(var.availability_domain, try(data.oci_identity_availability_domains.all.availability_domains[0].name, null))
  image_id            = coalesce(var.image_ocid, try(data.oci_core_images.ubuntu_arm.images[0].id, null))
}

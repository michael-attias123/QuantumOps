# Values come from infra/scripts/tofu.sh (TF_VAR_*), which reads ~/.oci/config and ~/.config/qops/*.env.
# Nothing here is committed with real values.

variable "region" {
  description = "OCI home region (Always Free A1 exists only there), e.g. il-jerusalem-1."
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID, from ~/.oci/config."
  type        = string
}

variable "oci_profile" {
  description = "Profile in ~/.oci/config used for API calls."
  type        = string
  default     = "DEFAULT"
}

variable "state_passphrase" {
  description = "Passphrase that encrypts OpenTofu state and plans (>= 16 chars). Keep a copy in your password manager."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "ssh_public_key" {
  description = "Break-glass SSH public key (contents of ~/.ssh/qops_oci.pub). Daily access uses Tailscale SSH."
  type        = string
}

variable "tailnet_dns_name" {
  description = "MagicDNS suffix of the tailnet, e.g. tail1234.ts.net. Added to the API server certificate."
  type        = string
}

variable "node_name" {
  description = "Hostname of the node, in OCI and on the tailnet."
  type        = string
  default     = "qops-node-1"
}

# The A1 guard (ADR 0008, ADR 0010): Always Free is 2 OCPU / 12 GB in total. During the Free Trial the console
# allows far more, but anything above this when the trial ends gets every A1 instance disabled and deleted.
variable "node_ocpus" {
  description = "A1 OCPUs for the node. Always Free allows 2 in total."
  type        = number
  default     = 2

  validation {
    condition     = var.node_ocpus >= 1 && var.node_ocpus <= 2
    error_message = "node_ocpus must be 1-2: more than the Always Free A1 allowance deletes all A1 VMs when the trial ends (ADR 0010)."
  }
}

variable "node_memory_gb" {
  description = "A1 memory in GB for the node. Always Free allows 12 in total."
  type        = number
  default     = 12

  validation {
    condition     = var.node_memory_gb >= 6 && var.node_memory_gb <= 12
    error_message = "node_memory_gb must be 6-12: more than the Always Free A1 allowance deletes all A1 VMs when the trial ends (ADR 0010)."
  }
}

variable "boot_volume_gb" {
  description = "Boot volume size. Always Free block storage is 200 GB in total."
  type        = number
  default     = 100

  validation {
    condition     = var.boot_volume_gb >= 50 && var.boot_volume_gb <= 200
    error_message = "boot_volume_gb must be 50-200 (Always Free block storage is 200 GB in total)."
  }
}

variable "ubuntu_version" {
  description = "Canonical Ubuntu release for the node image (aarch64)."
  type        = string
  default     = "24.04"
}

variable "image_ocid" {
  description = "Pin a specific node image. Default (null): the newest Canonical Ubuntu aarch64 image for A1."
  type        = string
  default     = null
}

variable "availability_domain" {
  description = "Availability domain for the node. Default (null): the region's first one."
  type        = string
  default     = null
}

variable "k3s_channel" {
  description = "k3s release channel installed at first boot (stable, latest, or e.g. v1.34)."
  type        = string
  default     = "stable"
}

variable "vcn_cidr" {
  description = "Private address range of the VCN. Must not overlap k3s pods (10.42.0.0/16) or services (10.43.0.0/16)."
  type        = string
  default     = "10.20.0.0/16"
}

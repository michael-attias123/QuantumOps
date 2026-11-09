terraform {
  required_version = ">= 1.10.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.12"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }

  # State lives in the OCI bucket made by `make oci-bootstrap`, through its S3-compatible API.
  # bucket, region and endpoints come from a backend file that infra/scripts/tofu.sh writes at init time;
  # credentials come from ~/.config/qops/oci.env (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
  backend "s3" {
    key                         = "oci/terraform.tfstate"
    use_path_style              = true
    use_lockfile                = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # State and plan files are encrypted before they leave this computer: they hold the node's
  # Tailscale auth key and resource IDs. The passphrase lives in ~/.config/qops/tofu.env only.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

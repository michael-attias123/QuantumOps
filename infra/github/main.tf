# Repository settings as code (P3). Token: GITHUB_TOKEN from `gh auth token`, set by infra/scripts/tofu.sh.

variable "state_passphrase" {
  description = "Passphrase that encrypts OpenTofu state and plans (shared with infra/oci)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
  default     = "michael-attias123"
}

variable "repository" {
  description = "Repository name."
  type        = string
  default     = "QuantumOps"
}

variable "required_checks" {
  description = "CI job names that must pass before a PR can merge into main (job `name:` in .github/workflows)."
  type        = list(string)
  default = [
    "lint & test (amd64)",
    "lint & test (arm64)",
    "pin matrix (amd64)",
    "pin matrix (arm64)",
    "opentofu (infra)",
    "deploy manifests",
    "secret scan",
  ]
}

provider "github" {
  owner = var.github_owner
}

# images.yml commits image tag bumps straight to main. On a personal (non-organization) account a ruleset can't
# exempt the GitHub Actions app, so the bump job pushes with this deploy key instead, and deploy keys may bypass.
# The private key lives only in the encrypted state and in the Actions secret; people still go through PRs.
resource "tls_private_key" "image_bump" {
  algorithm = "ED25519"
}

resource "github_repository_deploy_key" "image_bump" {
  repository = var.repository
  title      = "images.yml tag bump (managed by infra/github)"
  key        = tls_private_key.image_bump.public_key_openssh
  read_only  = false
}

resource "github_actions_secret" "image_bump" {
  repository      = var.repository
  secret_name     = "IMAGE_BUMP_DEPLOY_KEY"
  plaintext_value = tls_private_key.image_bump.private_key_openssh
}

resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = var.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_type  = "DeployKey"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = var.required_checks
        content {
          context = required_check.value
        }
      }
    }
  }
}

output "ruleset_id" {
  description = "ID of the main branch ruleset."
  value       = github_repository_ruleset.main.ruleset_id
}

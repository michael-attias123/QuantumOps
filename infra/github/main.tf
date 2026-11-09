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

locals {
  # The "GitHub Actions" app. Workflows push as this app with GITHUB_TOKEN; images.yml commits image tag bumps
  # straight to main, so it may bypass the PR rule. People still go through pull requests.
  github_actions_app_id = 15368
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
    actor_id    = local.github_actions_app_id
    actor_type  = "Integration"
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

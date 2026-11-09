# Offline checks with a mocked provider (runs in CI, no token needed).

mock_provider "github" {}

variables {
  state_passphrase = "test-passphrase-not-secret"
}

run "main_requires_prs_and_green_ci" {
  command = apply

  assert {
    condition     = github_repository_ruleset.main.enforcement == "active" && github_repository_ruleset.main.rules[0].deletion && github_repository_ruleset.main.rules[0].non_fast_forward
    error_message = "main must be protected against deletion and force pushes."
  }
  assert {
    condition     = length(github_repository_ruleset.main.rules[0].pull_request) == 1
    error_message = "Changes to main must go through a pull request."
  }
  assert {
    condition = alltrue([
      for c in ["lint & test (amd64)", "opentofu (infra)", "deploy manifests", "secret scan"] :
      contains([for r in github_repository_ruleset.main.rules[0].required_status_checks[0].required_check : r.context], c)
    ])
    error_message = "The main CI jobs must be required checks."
  }
  assert {
    condition     = length(github_repository_ruleset.main.bypass_actors) == 1 && github_repository_ruleset.main.bypass_actors[0].actor_type == "DeployKey"
    error_message = "Only deploy keys (the images.yml tag bump) may bypass the rules."
  }
  assert {
    condition     = !github_repository_deploy_key.image_bump.read_only && github_actions_secret.image_bump.secret_name == "IMAGE_BUMP_DEPLOY_KEY"
    error_message = "The bump deploy key must be writable and stored as the IMAGE_BUMP_DEPLOY_KEY Actions secret."
  }
}

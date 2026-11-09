# One-time setup before P2 (docs/phases/p2-prerequisites.md). Scripts live in infra/bootstrap/; all are idempotent.
# Pass extra flags with ARGS, e.g. `make oci-bootstrap ARGS=--dry-run`.
BOOTSTRAP := infra/bootstrap
ARGS ?=

.PHONY: tools tools-admin oci-login oci-bootstrap tailscale-login tailscale-check prereqs-report

tools: ## Install missing CLI tools on this computer (git, uv, kubectl, tailscale)
	bash $(BOOTSTRAP)/tools.sh $(ARGS)

tools-admin: ## Same, plus OpenTofu, OCI CLI and the SSH break-glass key (admin computer)
	bash $(BOOTSTRAP)/tools.sh --admin $(ARGS)

oci-login: ## Browser login to Oracle Cloud: creates the API key and ~/.oci/config
	bash $(BOOTSTRAP)/oci.sh login $(ARGS)

oci-bootstrap: ## OCI limits, budgets + alerts, state bucket, S3 key (-> ~/.config/qops/oci.env)
	bash $(BOOTSTRAP)/oci.sh all $(ARGS)

tailscale-login: ## Save a Tailscale API token (hidden prompt) and check the tailnet
	bash $(BOOTSTRAP)/tailscale.sh login $(ARGS)

tailscale-check: ## Check this computer's tailnet, MagicDNS and HTTPS settings
	bash $(BOOTSTRAP)/tailscale.sh check $(ARGS)

prereqs-report: ## Print the non-secret P2 values to paste in chat
	bash $(BOOTSTRAP)/report.sh

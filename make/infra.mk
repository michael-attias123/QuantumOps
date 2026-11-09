# P2: the cloud cluster (infra/oci). Run from the admin computer; secrets come from ~/.config/qops/*.env.
# Pass extra OpenTofu flags with ARGS, e.g. `make infra-plan ARGS=-target=oci_core_vcn.qops`.
TOFU_SH := bash infra/scripts/tofu.sh
NODE_SH := bash infra/scripts/node.sh

.PHONY: infra-check infra-init infra-plan infra-apply infra-rebuild infra-destroy infra-output kubeconfig ssh-server node-status

infra-check: ## Offline OpenTofu checks: fmt, validate, tests with mocked providers (no credentials)
	$(TOFU_SH) check

infra-init: ## Connect OpenTofu to the state bucket
	$(TOFU_SH) init $(ARGS)

infra-plan: ## Plan cloud changes and save the plan for review (changes nothing)
	$(TOFU_SH) plan $(ARGS)

infra-apply: ## Apply the reviewed plan from infra-plan
	$(TOFU_SH) apply

infra-rebuild: ## Plan a rebuild of the node with a fresh Tailscale key (review, then infra-apply)
	$(TOFU_SH) rebuild $(ARGS)

infra-destroy: ## Delete all P2 cloud resources (asks for confirmation)
	$(TOFU_SH) destroy $(ARGS)

infra-output: ## Show node name, public IP, KMS IDs
	$(TOFU_SH) output $(ARGS)

kubeconfig: ## Fetch the cluster kubeconfig over Tailscale (context "qops")
	$(NODE_SH) kubeconfig

ssh-server: ## Shell on the node over Tailscale SSH
	$(NODE_SH) ssh

node-status: ## First-boot progress on the node (cloud-init, k3s install log)
	$(NODE_SH) status

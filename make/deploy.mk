# P3: GitOps. `make bootstrap` installs Argo CD and the root Application; everything else comes from Git.
DEPLOY_SCRIPTS := deploy/bootstrap/scripts
# Keep tailnet traffic off corporate HTTP proxies (same rule as infra/bootstrap/lib.sh).
ON_TAILNET := NO_PROXY="100.64.0.0/10,.ts.net,$$NO_PROXY" no_proxy="100.64.0.0/10,.ts.net,$$no_proxy"

.PHONY: bootstrap deploy-check argocd-status argocd-password

bootstrap: ## Install the platform from Git onto the cluster (Argo CD + root app); safe to rerun
	bash $(DEPLOY_SCRIPTS)/bootstrap.sh

deploy-check: ## Offline: helm lint + render each env + kubeconform (same as CI)
	bash $(DEPLOY_SCRIPTS)/check.sh

argocd-status: ## Sync and health of every Argo CD Application
	$(ON_TAILNET) kubectl --context qops -n argocd get applications.argoproj.io

argocd-password: ## Copy the Argo CD admin password to the clipboard (prints it if there's no clipboard tool)
	@pw="$$($(ON_TAILNET) kubectl --context qops -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
	if command -v clip.exe >/dev/null; then printf '%s' "$$pw" | clip.exe; echo "copied to the Windows clipboard (user: admin)"; \
	elif command -v pbcopy >/dev/null; then printf '%s' "$$pw" | pbcopy; echo "copied to the clipboard (user: admin)"; \
	else echo "user: admin  password: $$pw"; fi

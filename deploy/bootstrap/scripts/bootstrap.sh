#!/usr/bin/env bash
# Install the platform from Git onto the cluster: the only imperative step of P3. Safe to rerun.
#   1. namespaces, and the Tailscale operator's OAuth Secret (from OpenTofu output; P4 moves it to Vault)
#   2. Argo CD via Helm, once; from then on Argo CD manages itself (the argo-cd Application)
#   3. the root Application, which renders deploy/apps for the oci environment
#   4. wait until every Application is Synced and Healthy
# shellcheck source=../../../infra/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../infra/bootstrap/lib.sh"
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need kubectl
need helm
need jq
need tofu

info "cluster: $(k config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
k get nodes >/dev/null || die "kubectl can't reach the cluster (context '$KUBE_CONTEXT'). Run: make kubeconfig"

info "namespaces"
k apply -f "$REPO_ROOT/deploy/platform/namespaces/namespaces.yaml" >/dev/null

info "Tailscale operator OAuth secret (from infra/oci output)"
client_id="$(tofu_output -raw k8s_operator_oauth_client_id)" || die "no OAuth client in the infra/oci state. Run: make infra-plan, make infra-apply"
# The secret goes from OpenTofu straight into the cluster through a pipe: never on disk, never on screen.
k -n tailscale create secret generic operator-oauth \
  --from-literal=client_id="$client_id" \
  --from-file=client_secret=<(tofu_output -raw k8s_operator_oauth_client_secret) \
  --dry-run=client -o json | k apply -f - >/dev/null
ok "tailscale/operator-oauth"

ARGO_REPO="$(app_field argo-cd repo)"
ARGO_VERSION="$(app_field argo-cd version)"
if k -n argocd get deployment argocd-server >/dev/null 2>&1; then
  ok "Argo CD already installed (it manages itself from Git now)"
else
  info "installing Argo CD chart $ARGO_VERSION (first time only)"
  helm --kube-context "$KUBE_CONTEXT" upgrade --install argocd argo-cd --repo "$ARGO_REPO" --version "$ARGO_VERSION" \
    --namespace argocd -f "$REPO_ROOT/deploy/platform/argo-cd/values.yaml" --wait --timeout 10m
fi

info "root Application"
k apply -f "$REPO_ROOT/deploy/bootstrap/root-app.yaml" >/dev/null

info "waiting for all Applications to be Synced and Healthy (up to 15 minutes)"
wait_apps 900
show_apps
ok "platform installed from Git"
info "Argo CD UI: https://argocd.$(tofu_output -raw tailnet_dns_name)  (user admin, password: make argocd-password)"

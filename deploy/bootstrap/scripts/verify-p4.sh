#!/usr/bin/env bash
# P4 Definition of Done checks against the live cluster and the shared Vault.
# shellcheck source=../../../infra/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../infra/bootstrap/lib.sh"
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need kubectl
need jq
need curl
failed=0
check() { if "$@"; then :; else failed=1; fi; }

vault_up() {
  local health
  health="$(curl -fsS --max-time 20 "$QOPS_VAULT_ADDR/v1/sys/health" 2>/dev/null | jq -c '{initialized, sealed}')" || health=""
  if [[ "$health" == '{"initialized":true,"sealed":false}' ]]; then ok "shared Vault is up: $QOPS_VAULT_ADDR"; else
    warn "shared Vault not healthy at $QOPS_VAULT_ADDR: ${health:-no answer}"
    return 1
  fi
}

condition() { # KIND NAME [NAMESPACE] -> "status reason" of its Ready condition
  local ns=()
  [[ -n "${3:-}" ]] && ns=(-n "$3")
  k "${ns[@]}" get "$1" "$2" -o json 2>/dev/null |
    jq -r '[.status.conditions[]? | select(.type == "Ready")][0] | "\(.status // "?") \(.reason // "?")"'
}

store_ready() {
  local c
  c="$(condition clustersecretstore vault)"
  if [[ "$c" == "True "* ]]; then ok "ClusterSecretStore vault is Ready (ESO logged in to Vault)"; else
    warn "ClusterSecretStore vault is not Ready ($c). See: kubectl --context $KUBE_CONTEXT describe clustersecretstore vault"
    return 1
  fi
}

synced() {
  local c
  c="$(condition externalsecret operator-oauth tailscale)"
  if [[ "$c" == "True SecretSynced" ]]; then ok "ExternalSecret tailscale/operator-oauth: SecretSynced"; else
    warn "ExternalSecret tailscale/operator-oauth: $c (seeded? make seed-secrets)"
    return 1
  fi
}

owned_by_eso() {
  local owner
  owner="$(k -n tailscale get secret operator-oauth -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)"
  if [[ "$owner" == "ExternalSecret" ]]; then ok "Secret tailscale/operator-oauth is owned by its ExternalSecret"; else
    warn "Secret tailscale/operator-oauth is not owned by ESO (owner: ${owner:-none})"
    return 1
  fi
}

comes_back() {
  info "deleting Secret tailscale/operator-oauth; ESO must recreate it from Vault"
  k -n tailscale delete secret operator-oauth --wait=true >/dev/null
  k -n tailscale annotate externalsecret operator-oauth force-sync="$(date +%s)" --overwrite >/dev/null
  local waited=0
  while ((waited < 60)); do
    if k -n tailscale get secret operator-oauth >/dev/null 2>&1; then
      ok "recreated from Vault after ${waited}s"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  warn "Secret tailscale/operator-oauth not back after 60s"
  return 1
}

operator_running() {
  if k -n tailscale rollout status deployment/operator --timeout=180s >/dev/null 2>&1; then
    ok "Tailscale operator is running with the Vault-sourced credentials"
  else
    warn "Tailscale operator isn't ready: kubectl --context $KUBE_CONTEXT -n tailscale logs deployment/operator"
    return 1
  fi
}

check vault_up
check store_ready
check synced
check owned_by_eso
check comes_back
check operator_running
((failed == 0)) || die "P4 checks failed"
ok "P4 checks passed"

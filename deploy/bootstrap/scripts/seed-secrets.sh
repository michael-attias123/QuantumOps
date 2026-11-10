#!/usr/bin/env bash
# P4: copy the secrets that QuantumOps' own OpenTofu state holds into the shared Vault. Safe to rerun: it writes only
# when a value changed. Values never reach the screen, the command line or the repo.
#   kv/quantumops/tailscale   oauth_client_id, oauth_client_secret   (infra/oci tailscale_oauth_client)
# Needs a Vault admin login first: in ~/shared-platform, make vault-login (password + code; leaves ~/.vault-token).
# shellcheck source=../../../infra/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../infra/bootstrap/lib.sh"
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need vault
need jq
need tofu
export VAULT_ADDR="$QOPS_VAULT_ADDR"
vault token lookup >/dev/null 2>&1 || die "not logged in to $VAULT_ADDR. In ~/shared-platform run: make vault-login"

mkdir -p "$QOPS_CONFIG_DIR"
work="$(mktemp -d "$QOPS_CONFIG_DIR/seed.XXXXXX")"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

tofu_output -raw k8s_operator_oauth_client_id >"$work/id" 2>/dev/null || true
tofu_output -raw k8s_operator_oauth_client_secret >"$work/secret" 2>/dev/null || true
[[ -s "$work/id" && -s "$work/secret" ]] || die "no OAuth client in the infra/oci state. Run: make infra-plan, make infra-apply"
jq -n --rawfile id "$work/id" --rawfile secret "$work/secret" \
  '{oauth_client_id: $id, oauth_client_secret: $secret}' >"$work/new.json"

path="quantumops/tailscale"
if vault kv get -mount=kv -format=json "$path" 2>/dev/null | jq -S '.data.data' >"$work/current.json" &&
  jq -S . "$work/new.json" | cmp -s - "$work/current.json"; then
  ok "kv/$path: oauth_client_id, oauth_client_secret already up to date"
else
  vault kv put -mount=kv "$path" - <"$work/new.json" >/dev/null
  ok "kv/$path: oauth_client_id, oauth_client_secret written"
fi
info "ESO copies it into tailscale/operator-oauth within the hour; to sync now: make secrets-sync"

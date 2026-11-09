#!/usr/bin/env bash
# Run OpenTofu for infra/oci with credentials from the local secret files (never from the repo).
#   Usage: tofu.sh init | plan | apply | rebuild | destroy | output | check | <any tofu subcommand> [args]
#
#   init     connect to the state bucket (runs automatically when needed)
#   plan     save a plan to review; nothing changes yet
#   apply    apply the saved plan (and only that plan)
#   rebuild  plan a fresh node + fresh Tailscale key (cluster rebuild); then `apply`
#   check    offline: fmt, validate, tests with mocked providers (no credentials; same as CI)
#
# Reads: ~/.oci/config, ~/.config/qops/{oci,tailscale,tofu}.env, ~/.ssh/qops_oci.pub, the tailnet name.
# shellcheck source=../bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STACK="$REPO_ROOT/infra/oci"
PLAN_FILE="$STACK/.terraform/qops.tfplan"
OCI_ENV="$QOPS_CONFIG_DIR/oci.env"
TS_ENV="$QOPS_CONFIG_DIR/tailscale.env"
TOFU_ENV="$QOPS_CONFIG_DIR/tofu.env"
BACKEND_FILE="$QOPS_CONFIG_DIR/backend-oci.hcl"
SSH_PUB="${QOPS_SSH_PUBLIC_KEY:-$HOME/.ssh/qops_oci.pub}"

tf() { tofu -chdir="$STACK" "$@"; }

offline_check() {
  tofu fmt -check -recursive "$REPO_ROOT/infra"
  tf init -backend=false -input=false >/dev/null
  tf validate
  tf test
}

ensure_passphrase() {
  [[ -n "$(env_file_get "$TOFU_ENV" TF_VAR_state_passphrase)" ]] && return
  info "creating the state encryption passphrase -> $TOFU_ENV"
  local pass
  pass="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
  printf '# QuantumOps OpenTofu state encryption passphrase. Secret: never commit, never paste.\nTF_VAR_state_passphrase=%s\n' \
    "$pass" | write_secret_file "$TOFU_ENV"
  warn "SAVE IT NOW: copy the value from $TOFU_ENV into your password manager."
  warn "Without it the encrypted state can't be read (the cluster can still be rebuilt, but not managed)."
}

load_env() {
  [[ -f "$OCI_ENV" ]] || die "missing $OCI_ENV. Run: make oci-bootstrap"
  [[ -f "$TS_ENV" ]] || die "missing $TS_ENV. Run: make tailscale-login"
  [[ -f "$SSH_PUB" ]] || die "missing $SSH_PUB. Run: make tools-admin"
  ensure_passphrase
  set -a
  # shellcheck disable=SC1090
  source "$OCI_ENV"
  # shellcheck disable=SC1090
  source "$TS_ENV"
  # shellcheck disable=SC1090
  source "$TOFU_ENV"
  set +a

  local ts suffix
  ts="$(ts_cmd)"
  [[ -n "$ts" ]] || die "tailscale not found. Run: make tools (or install Tailscale on Windows for WSL)"
  suffix="$("$ts" status --json 2>/dev/null | jq -r '.MagicDNSSuffix // .CurrentTailnet.MagicDNSSuffix // empty')"
  [[ -n "$suffix" ]] || die "this computer isn't on the tailnet. Run: tailscale up"

  export TF_VAR_region="$QOPS_OCI_REGION"
  TF_VAR_tenancy_ocid="$(oci_cfg tenancy)"
  export TF_VAR_tenancy_ocid
  export TF_VAR_oci_profile="$OCI_CLI_PROFILE"
  TF_VAR_ssh_public_key="$(cat "$SSH_PUB")"
  export TF_VAR_ssh_public_key
  export TF_VAR_tailnet_dns_name="$suffix"
  [[ -n "$TF_VAR_tenancy_ocid" ]] || die "no tenancy in $OCI_CONFIG_FILE. Run: make oci-login"

  # Not secret: where the state lives.
  mkdir -p "$QOPS_CONFIG_DIR"
  cat >"$BACKEND_FILE" <<EOF
bucket    = "$QOPS_STATE_BUCKET"
region    = "$QOPS_OCI_REGION"
endpoints = { s3 = "https://$QOPS_OCI_NAMESPACE.compat.objectstorage.$QOPS_OCI_REGION.oci.customer-oci.com" }
EOF
}

init() { tf init -input=false -reconfigure -backend-config="$BACKEND_FILE" "$@"; }
ensure_init() { [[ -f "$STACK/.terraform/terraform.tfstate" ]] || init >/dev/null; }

need tofu
need jq
CMD="${1:-plan}"
shift || true
case "$CMD" in
  check)
    offline_check
    exit
    ;;
esac

load_env
case "$CMD" in
  init) init "$@" ;;
  plan)
    ensure_init
    tf plan -input=false -out="$PLAN_FILE" "$@"
    info "review the plan above; if it's right: make infra-apply"
    ;;
  rebuild)
    ensure_init
    tf plan -input=false -out="$PLAN_FILE" \
      -replace=oci_core_instance.node -replace=tailscale_tailnet_key.node "$@"
    warn "this plan DESTROYS the node and creates a new one (cluster data on it is lost; Git + Vault restore it)"
    info "remove the old '${TF_VAR_node_name:-qops-node-1}' from https://login.tailscale.com/admin/machines after apply"
    info "if it's right: make infra-apply"
    ;;
  apply)
    [[ -f "$PLAN_FILE" ]] || die "no saved plan. Run: make infra-plan (and review it) first"
    ensure_init
    tf apply -input=false "$PLAN_FILE"
    rm -f "$PLAN_FILE"
    info "the node needs ~5 minutes for first boot. Then: make kubeconfig"
    ;;
  destroy)
    ensure_init
    warn "this deletes the cluster VM, network, KMS key (7-day pending deletion) and the tailnet policy stays as is"
    tf destroy -input=false "$@"
    ;;
  *)
    ensure_init
    tf "$CMD" "$@"
    ;;
esac

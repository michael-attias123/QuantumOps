#!/usr/bin/env bash
# Run OpenTofu for an infra stack with credentials from the local secret files (never from the repo).
#   Usage: [QOPS_STACK=oci|github] tofu.sh init | plan | apply | rebuild | destroy | output | check | <tofu cmd> [args]
#
#   init     connect to the state bucket (runs automatically when needed)
#   plan     save a plan to review; nothing changes yet
#   apply    apply the saved plan (and only that plan)
#   rebuild  (oci) plan a fresh node + fresh Tailscale key (cluster rebuild); then `apply`
#   check    offline, all stacks: fmt, validate, tests with mocked providers (no credentials; same as CI)
#
# Stacks: infra/oci (default; the cluster) and infra/github (repository settings).
# Reads: ~/.oci/config, ~/.config/qops/{oci,tailscale,tofu}.env, ~/.ssh/qops_oci.pub, the tailnet name,
# and for github a token from `gh auth token`.
# shellcheck source=../bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STACK_NAME="${QOPS_STACK:-oci}"
STACKS=(oci github)
STACK="$REPO_ROOT/infra/$STACK_NAME"
PLAN_FILE="$STACK/.terraform/qops.tfplan"
OCI_ENV="$QOPS_CONFIG_DIR/oci.env"
TS_ENV="$QOPS_CONFIG_DIR/tailscale.env"
TOFU_ENV="$QOPS_CONFIG_DIR/tofu.env"
BACKEND_FILE="$QOPS_CONFIG_DIR/backend-oci.hcl"
SSH_PUB="${QOPS_SSH_PUBLIC_KEY:-$HOME/.ssh/qops_oci.pub}"
[[ -d "$STACK" ]] || die "unknown stack '$STACK_NAME' (one of: ${STACKS[*]})"
APPLY_TARGET="infra-apply"
[[ "$STACK_NAME" == "github" ]] && APPLY_TARGET="github-apply"

tf() { tofu -chdir="$STACK" "$@"; }

offline_check() {
  local s
  tofu fmt -check -recursive "$REPO_ROOT/infra"
  for s in "${STACKS[@]}"; do
    info "infra/$s"
    tofu -chdir="$REPO_ROOT/infra/$s" init -backend=false -input=false >/dev/null
    tofu -chdir="$REPO_ROOT/infra/$s" validate
    tofu -chdir="$REPO_ROOT/infra/$s" test
  done
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

github_token() {
  local gh
  for gh in gh gh.exe; do
    if have "$gh" && "$gh" auth token 2>/dev/null | tr -d '\r'; then return; fi
  done
  return 1
}

load_common_env() {
  # shellcheck disable=SC2218 # false positive: die comes from lib.sh, sourced at the top
  [[ -f "$OCI_ENV" ]] || die "missing $OCI_ENV. Run: make oci-bootstrap"
  ensure_passphrase
  set -a
  # shellcheck disable=SC1090
  source "$OCI_ENV"
  # shellcheck disable=SC1090
  source "$TOFU_ENV"
  set +a

  # Not secret: where the state lives (shared by all stacks; each stack has its own key).
  mkdir -p "$QOPS_CONFIG_DIR"
  cat >"$BACKEND_FILE" <<EOF
bucket    = "$QOPS_STATE_BUCKET"
region    = "$QOPS_OCI_REGION"
endpoints = { s3 = "https://$QOPS_OCI_NAMESPACE.compat.objectstorage.$QOPS_OCI_REGION.oci.customer-oci.com" }
EOF
}

load_oci_env() {
  [[ -f "$TS_ENV" ]] || die "missing $TS_ENV. Run: make tailscale-login"
  [[ -f "$SSH_PUB" ]] || die "missing $SSH_PUB. Run: make tools-admin"
  set -a
  # shellcheck disable=SC1090
  source "$TS_ENV"
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
}

load_env() {
  load_common_env
  case "$STACK_NAME" in
    oci) load_oci_env ;;
    github)
      [[ -n "${GITHUB_TOKEN:-}" ]] || GITHUB_TOKEN="$(github_token)" ||
        die "no GitHub token. Log in once with: gh auth login (or gh.exe on Windows)"
      export GITHUB_TOKEN
      ;;
  esac
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
    info "review the plan above; if it's right: make $APPLY_TARGET"
    ;;
  rebuild)
    [[ "$STACK_NAME" == "oci" ]] || die "rebuild applies to the oci stack only"
    ensure_init
    tf plan -input=false -out="$PLAN_FILE" \
      -replace=oci_core_instance.node -replace=tailscale_tailnet_key.node "$@"
    warn "this plan DESTROYS the node and creates a new one (cluster data on it is lost; Git + Vault restore it)"
    info "remove the old '${TF_VAR_node_name:-qops-node-1}' from https://login.tailscale.com/admin/machines after apply"
    info "if it's right: make infra-apply, then make bootstrap"
    ;;
  apply)
    [[ -f "$PLAN_FILE" ]] || die "no saved plan. Run the matching plan target (and review it) first"
    ensure_init
    tf apply -input=false "$PLAN_FILE" | tee "$STACK/.terraform/last-apply.log"
    rm -f "$PLAN_FILE"
    if [[ "$STACK_NAME" == "oci" ]] && grep -q 'oci_core_instance.node: Creation complete' "$STACK/.terraform/last-apply.log"; then
      info "new node: first boot takes ~5 minutes. Then: make kubeconfig && make bootstrap"
    fi
    ;;
  destroy)
    ensure_init
    [[ "$STACK_NAME" == "oci" ]] &&
      warn "this deletes the cluster VM, network, KMS key (7-day pending deletion); the tailnet policy stays as is"
    tf destroy -input=false "$@"
    ;;
  *)
    ensure_init
    tf "$CMD" "$@"
    ;;
esac

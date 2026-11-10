#!/usr/bin/env bash
# Oracle Cloud one-time setup for P2, through the OCI CLI. Idempotent: safe to rerun.
#   Usage: oci.sh [--dry-run] [login|limits|budgets|bucket|secret-key|all] [--rotate-secret-key]
#
#   login       browser login; creates the API key pair and ~/.oci/config (`oci setup bootstrap`)
#   limits      prints Ampere A1 and GPU A10 limits and an estimated trial end date
#   budgets     checks the $1 budget and its alerts exist (owned by shared-platform stacks/oci-foundation)
#   bucket      checks the versioned OpenTofu state bucket exists (owned by shared-platform stacks/oci-foundation)
#   secret-key  S3-compatible key for the state bucket -> ~/.config/qops/oci.env (0600, never printed)
#   all         limits, budgets, bucket, secret-key (default)
#
# Env: OCI_CLI_PROFILE (DEFAULT), QOPS_STATE_BUCKET (qops-tofu-state).
#
# The state bucket and the budget are shared by every project, so shared-platform's stacks/oci-foundation owns them
# (imported, prevent_destroy). This script only checks them; fix anything it reports there, not here.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_args "$@"

STEP="all"
ROTATE=0
for a in "${ARGS[@]+"${ARGS[@]}"}"; do
  case "$a" in
    login | limits | budgets | bucket | secret-key | all) STEP="$a" ;;
    --rotate-secret-key) ROTATE=1 ;;
    *) die "unknown argument: $a" ;;
  esac
done

BUCKET="${QOPS_STATE_BUCKET:-qops-tofu-state}"
SECRET_KEY_NAME="qops-tofu"
OCI_ENV="$QOPS_CONFIG_DIR/oci.env"
BUDGET_NAME="qops-always-free"

ocij() { oci --profile "$OCI_CLI_PROFILE" --output json "$@"; }

load_identity() {
  [[ -f "$OCI_CONFIG_FILE" ]] || die "no $OCI_CONFIG_FILE yet. Run: make oci-login"
  TENANCY="$(oci_cfg tenancy)"
  USER_OCID="$(oci_cfg user)"
  REGION="$(oci_cfg region)"
  [[ -n "$TENANCY" && -n "$USER_OCID" && -n "$REGION" ]] ||
    die "profile [$OCI_CLI_PROFILE] in $OCI_CONFIG_FILE lacks tenancy/user/region"
  ocij iam region-subscription list --tenancy-id "$TENANCY" >/dev/null ||
    die "the OCI API rejected the credentials in $OCI_CONFIG_FILE. Rerun: make oci-login"
}

step_login() {
  need oci
  if [[ -f "$OCI_CONFIG_FILE" ]] && [[ -n "$(oci_cfg tenancy)" ]]; then
    ok "$OCI_CONFIG_FILE already has profile [$OCI_CLI_PROFILE]; delete it first to log in again"
    return
  fi
  info "a browser window opens: log in to Oracle Cloud, then return here"
  info "answers: pick your HOME region; no passphrase for the API key"
  run oci setup bootstrap --profile-name "$OCI_CLI_PROFILE" --config-location "$OCI_CONFIG_FILE"
  run chmod 600 "$OCI_CONFIG_FILE"
}

# Sum an AD-scoped compute limit over all availability domains.
limit_sum() {
  ocij limits value list --compartment-id "$TENANCY" --service-name compute --name "$1" --all 2>/dev/null |
    jq '[.data[]?.value // 0] | add // 0'
}

step_limits() {
  local a1_core a1_mem gpu created
  a1_core="$(limit_sum standard-a1-core-count)"
  a1_mem="$(limit_sum standard-a1-memory-count)"
  gpu="$(limit_sum gpu-a10-count)"
  info "limits in $REGION"
  printf '   Ampere A1: %s OCPU / %s GB\n' "$a1_core" "$a1_mem"
  printf '   GPU A10:   %s\n' "$gpu"
  if ((a1_core > 2)); then
    warn "these are trial limits. We still build for 2 OCPU / 12 GB (ADR 0010): more A1 at trial end deletes all A1 VMs"
  fi
  if [[ "$gpu" == "0" ]]; then
    warn "GPU A10 limit is 0. Request 1 here (one-time form; optional, ADR 0010):"
    printf '   https://cloud.oracle.com/limits?region=%s  -> Request a service limit update -> Compute, GPU A10\n' "$REGION"
  fi
  created="$(ocij iam compartment get --compartment-id "$TENANCY" 2>/dev/null | jq -r '.data."time-created" // empty')"
  if [[ -n "$created" ]]; then
    printf '   Trial ends about: %s (tenancy created %s + 30 days; confirm under Billing -> Subscriptions)\n' \
      "$(trial_end "$created")" "${created%%T*}"
  fi
}

trial_end() {
  local d="${1%%T*}"
  date -u -d "$d + 30 days" +%F 2>/dev/null || date -u -j -v+30d -f %F "$d" +%F
}

budget_id() {
  ocij budgets budget budget list --compartment-id "$TENANCY" --all 2>/dev/null |
    jq -r --arg n "$1" '.data[]? | select(."display-name" == $n) | .id' | head -n1
}

OWNER_HINT="it's owned by shared-platform: make plan STACK=oci-foundation, then make apply STACK=oci-foundation"

step_budgets() {
  local id rules
  id="$(budget_id "$BUDGET_NAME")"
  if [[ -z "$id" ]]; then
    warn "budget $BUDGET_NAME is missing; $OWNER_HINT"
    return
  fi
  rules="$(ocij budgets budget alert-rule list --budget-id "$id" --all 2>/dev/null | jq -r '.data | length')"
  ok "budget $BUDGET_NAME ($rules alerts; owned by shared-platform)"
}

step_bucket() {
  NAMESPACE="$(ocij os ns get | jq -r .data)"
  local versioning
  versioning="$(ocij os bucket get --namespace-name "$NAMESPACE" --bucket-name "$BUCKET" 2>/dev/null |
    jq -r '.data.versioning // empty' || true)"
  if [[ -z "$versioning" ]]; then
    warn "bucket $BUCKET is missing; $OWNER_HINT"
  elif [[ "$versioning" != "Enabled" ]]; then
    warn "bucket $BUCKET has versioning $versioning (should be Enabled); $OWNER_HINT"
  else
    ok "bucket $BUCKET (versioned; owned by shared-platform)"
  fi
  printf '   namespace: %s
   S3 endpoint: https://%s.compat.objectstorage.%s.oci.customer-oci.com
' \
    "$NAMESPACE" "$NAMESPACE" "$REGION"
}

step_secret_key() {
  local existing
  existing="$(ocij iam customer-secret-key list --user-id "$USER_OCID" 2>/dev/null |
    jq -r --arg n "$SECRET_KEY_NAME" '.data[]? | select(."display-name" == $n) | .id' | head -n1)"
  if [[ -n "$existing" && -n "$(env_file_get "$OCI_ENV" AWS_SECRET_ACCESS_KEY)" && "$ROTATE" == "0" ]]; then
    ok "S3 key $SECRET_KEY_NAME (saved in $OCI_ENV)"
    return
  fi
  if [[ -n "$existing" ]]; then
    if [[ "$ROTATE" == "0" ]]; then
      die "key $SECRET_KEY_NAME exists in OCI but not in $OCI_ENV (its secret is shown only once). Rerun: make oci-bootstrap ARGS=--rotate-secret-key"
    fi
    info "deleting old S3 key $SECRET_KEY_NAME"
    run oci --profile "$OCI_CLI_PROFILE" iam customer-secret-key delete --user-id "$USER_OCID" \
      --customer-secret-key-id "$existing" --force
  fi
  info "creating S3 key $SECRET_KEY_NAME -> $OCI_ENV"
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run oci iam customer-secret-key create --user-id "$USER_OCID" --display-name "$SECRET_KEY_NAME"
    printf '' | write_secret_file "$OCI_ENV"
    return
  fi
  local created namespace
  created="$(ocij iam customer-secret-key create --user-id "$USER_OCID" --display-name "$SECRET_KEY_NAME")"
  namespace="${NAMESPACE:-$(ocij os ns get | jq -r .data)}"
  jq -r --arg ns "$namespace" --arg region "$REGION" --arg bucket "$BUCKET" '
    "# QuantumOps OpenTofu state backend credentials. Secret: never commit, never paste.",
    "AWS_ACCESS_KEY_ID=\(.data.id)",
    "AWS_SECRET_ACCESS_KEY=\(.data.key)",
    "QOPS_OCI_NAMESPACE=\($ns)",
    "QOPS_OCI_REGION=\($region)",
    "QOPS_STATE_BUCKET=\($bucket)"' <<<"$created" | write_secret_file "$OCI_ENV"
  ok "saved (new keys can take a few minutes to start working)"
}

need jq
case "$STEP" in
  login) step_login ;;
  *)
    need oci
    load_identity
    case "$STEP" in
      limits) step_limits ;;
      budgets) step_budgets ;;
      bucket) step_bucket ;;
      secret-key) step_secret_key ;;
      all)
        step_limits
        step_budgets
        step_bucket
        step_secret_key
        info "done. Next: make tailscale-login, then make prereqs-report"
        ;;
    esac
    ;;
esac

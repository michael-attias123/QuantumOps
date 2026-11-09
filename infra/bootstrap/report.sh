#!/usr/bin/env bash
# Print the non-secret values P2 needs, ready to paste in chat. Read-only; never prints a secret.
#   Usage: report.sh
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mark() { if "$@" >/dev/null 2>&1; then printf '[x]'; else printf '[ ]'; fi; }
ver() { have "$1" && "$@" 2>/dev/null | head -n1 || echo "not installed"; }

REGION="$(oci_cfg region)"
TENANCY="$(oci_cfg tenancy)"
BUCKET="${QOPS_STATE_BUCKET:-qops-tofu-state}"
OCI_OK=0
A1="?" GPU="?" NAMESPACE="?" TRIAL="?" BUDGETS=0 VERSIONED=0
if have oci && have jq && [[ -n "$TENANCY" ]] &&
  NAMESPACE="$(oci --profile "$OCI_CLI_PROFILE" os ns get 2>/dev/null | jq -r .data)"; then
  OCI_OK=1
  sum() {
    oci --profile "$OCI_CLI_PROFILE" limits value list --compartment-id "$TENANCY" --service-name compute \
      --name "$1" --all 2>/dev/null | jq '[.data[]?.value // 0] | add // 0'
  }
  A1="$(sum standard-a1-core-count) OCPU / $(sum standard-a1-memory-count) GB"
  GPU="$(sum gpu-a10-count)"
  created="$(oci --profile "$OCI_CLI_PROFILE" iam compartment get --compartment-id "$TENANCY" 2>/dev/null |
    jq -r '.data."time-created" // empty')"
  if [[ -n "$created" ]]; then
    TRIAL="$(date -u -d "${created%%T*} + 30 days" +%F 2>/dev/null ||
      date -u -j -v+30d -f %F "${created%%T*}" +%F) (estimate)"
  fi
  BUDGETS="$(oci --profile "$OCI_CLI_PROFILE" budgets budget list --compartment-id "$TENANCY" --all 2>/dev/null |
    jq '[.data[]? | select(."display-name" | startswith("qops-"))] | length')"
  [[ "$(oci --profile "$OCI_CLI_PROFILE" os bucket get --namespace-name "$NAMESPACE" --bucket-name "$BUCKET" \
    2>/dev/null | jq -r '.data.versioning // empty')" == "Enabled" ]] && VERSIONED=1
else
  NAMESPACE="?"
fi

TAILNET="?" TS_RUNNING=0 TS_HTTPS=0
TS="$(ts_cmd)"
if [[ -n "$TS" ]] && status="$("$TS" status --json 2>/dev/null)"; then
  TAILNET="$(jq -r '.MagicDNSSuffix // .CurrentTailnet.MagicDNSSuffix // "?"' <<<"$status")"
  [[ "$(jq -r .BackendState <<<"$status")" == "Running" ]] && TS_RUNNING=1
  (($(jq -r '(.CertDomains // []) | length' <<<"$status") > 0)) && TS_HTTPS=1
fi

yes() { [[ "$1" == "1" ]]; }
nonempty() { [[ -n "$(env_file_get "$1" "$2")" ]]; }

cat <<EOF
--- QuantumOps P2 prerequisites (no secrets) ---
OCI home region:            ${REGION:-?}
Ampere A1 limits:           $A1
GPU A10 limit:              $GPU
Trial end date:             $TRIAL
Object Storage namespace:   $NAMESPACE
State bucket:               $BUCKET
Tailnet DNS name:           $TAILNET
This computer's OS:         $(os_name) ($(uname -m))
Checklist:                  $(mark yes "$OCI_OK") OCI API login works  $(mark test "$BUDGETS" -ge 2) budgets ($BUDGETS/2)  $(mark yes "$VERSIONED") bucket versioned
                            $(mark nonempty "$QOPS_CONFIG_DIR/oci.env" AWS_SECRET_ACCESS_KEY) S3 key saved  $(mark nonempty "$QOPS_CONFIG_DIR/tailscale.env" TAILSCALE_API_KEY) Tailscale token saved
                            $(mark yes "$TS_RUNNING") on the tailnet  $(mark yes "$TS_HTTPS") HTTPS certificates  $(mark test -f "$HOME/.ssh/qops_oci.pub") SSH key
Tools:                      tofu $(have tofu && tofu version -json 2>/dev/null | jq -r .terraform_version || echo "not installed")
                            kubectl $(have kubectl && kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion || echo "not installed")
                            tailscale $([[ -n "$TS" ]] && "$TS" version 2>/dev/null | head -n1 || echo "not installed")
                            oci $(ver oci --version)
                            uv $(ver uv --version)
---
EOF

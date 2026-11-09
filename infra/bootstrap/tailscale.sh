#!/usr/bin/env bash
# Tailscale setup checks for P2, and a safe place for the API access token.
#   Usage: tailscale.sh [--dry-run] [login|check]
#
#   login  hidden prompt for a Tailscale API access token -> ~/.config/qops/tailscale.env (0600), then check
#   check  this computer is on the tailnet; MagicDNS name; HTTPS certificates on; token valid (default)
#
# P2's OpenTofu uses the token (TAILSCALE_API_KEY) to write the tailnet policy from Git and to mint a short-lived,
# tagged auth key for the node, so you never create or paste an auth key yourself.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_args "$@"

STEP="check"
for a in "${ARGS[@]+"${ARGS[@]}"}"; do
  case "$a" in
    login | check) STEP="$a" ;;
    *) die "unknown argument: $a" ;;
  esac
done

TS_ENV="$QOPS_CONFIG_DIR/tailscale.env"
TS_API="${QOPS_TAILSCALE_API:-https://api.tailscale.com/api/v2}"

# Calls the API with the token passed through a curl config on stdin, so it never shows up in `ps`.
token_valid() {
  local token="$1"
  printf 'user = "%s:"\n' "$token" |
    curl -fsS -o /dev/null -K - "$TS_API/tailnet/-/devices?fields=default" 2>/dev/null
}

step_login() {
  need curl
  local token
  if [[ -n "$(env_file_get "$TS_ENV" TAILSCALE_API_KEY)" ]]; then
    ok "token already saved in $TS_ENV (delete the file to replace it)"
    return
  fi
  cat <<'EOF'
Create the token at https://login.tailscale.com/admin/settings/keys -> "Generate access token":
  description qops-tofu, expiry 90 days. Copy it (starts with tskey-api-), then paste it below.
  The input is hidden and goes only to ~/.config/qops/tailscale.env. Never paste it in chat.
EOF
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    printf '' | write_secret_file "$TS_ENV"
    return
  fi
  read -r -s -p "Tailscale API access token: " token
  echo
  [[ "$token" == tskey-api-* ]] || die "that doesn't look like an API access token (expected tskey-api-...)"
  token_valid "$token" || die "Tailscale rejected the token; check it wasn't truncated"
  printf '# QuantumOps Tailscale API token for OpenTofu. Secret: never commit, never paste.\nTAILSCALE_API_KEY=%s\nTAILSCALE_TAILNET=-\n' \
    "$token" | write_secret_file "$TS_ENV"
  ok "saved $TS_ENV"
}

step_check() {
  local status state suffix certs token ts
  ts="$(ts_cmd)"
  if [[ -n "$ts" ]] && status="$("$ts" status --json 2>/dev/null)"; then
    state="$(jq -r '.BackendState // empty' <<<"$status")"
    suffix="$(jq -r '.MagicDNSSuffix // .CurrentTailnet.MagicDNSSuffix // empty' <<<"$status")"
    certs="$(jq -r '(.CertDomains // []) | length' <<<"$status")"
    if [[ "$state" == "Running" ]]; then ok "this computer is on the tailnet"; else warn "tailscale state: ${state:-unknown}. Run: tailscale up"; fi
    if [[ -n "$suffix" ]]; then ok "tailnet DNS name $suffix"; else warn "MagicDNS is off (P2's OpenTofu turns it on)"; fi
    if ((certs > 0)); then
      ok "HTTPS certificates on"
    else
      warn "HTTPS certificates look off. Turn them on: https://login.tailscale.com/admin/dns -> Enable HTTPS"
    fi
  else
    warn "tailscale is not running here. Run: make tools, then tailscale up"
  fi
  token="$(env_file_get "$TS_ENV" TAILSCALE_API_KEY)"
  if [[ -z "$token" ]]; then
    warn "no API token saved. Run: make tailscale-login"
  elif token_valid "$token"; then
    ok "API token valid"
  else
    warn "API token rejected (expired?). Delete $TS_ENV and run: make tailscale-login"
  fi
}

need jq
case "$STEP" in
  login)
    step_login
    step_check
    ;;
  check) step_check ;;
esac

# shellcheck shell=bash
# Helpers shared by the deploy scripts. Sourced after infra/bootstrap/lib.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KUBE_CONTEXT="${QOPS_KUBE_CONTEXT:-qops}"
export PATH="$HOME/.local/bin:$PATH"

k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

tofu_output() { bash "$REPO_ROOT/infra/scripts/tofu.sh" output "$@"; }

# A field of an app's upstream chart in deploy/apps/values.yaml, e.g. `app_field argo-cd version`.
app_field() {
  awk -v app="  $1:" -v field="$2" '
    $0 == app { in_app = 1; next }
    in_app && /^  [a-z]/ { exit }
    in_app && $1 == field ":" { print $2; exit }' "$REPO_ROOT/deploy/apps/values.yaml"
}

apps_json() { k -n argocd get applications.argoproj.io -o json 2>/dev/null || echo '{"items":[]}'; }

show_apps() {
  apps_json | jq -r '.items[] | [.metadata.name, (.status.sync.status // "?"), (.status.health.status // "?")] | @tsv' |
    awk 'BEGIN { printf "   %-20s %-10s %s\n", "APP", "SYNC", "HEALTH" } { printf "   %-20s %-10s %s\n", $1, $2, $3 }'
}

# Wait until there are Applications and all are Synced + Healthy.
wait_apps() {
  local timeout="$1" waited=0 pending
  while ((waited < timeout)); do
    pending="$(apps_json | jq -r '
      if (.items | length) < 2 then "none yet"
      else [.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy") | .metadata.name] | join(" ")
      end')"
    [[ -z "$pending" ]] && return 0
    printf '   waiting (%ss): %s\n' "$waited" "$pending"
    sleep 15
    waited=$((waited + 15))
  done
  show_apps
  die "not all Applications are Synced and Healthy after ${timeout}s. Look at them: make argocd-status"
}

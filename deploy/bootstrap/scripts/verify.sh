#!/usr/bin/env bash
# P3 Definition of Done checks against the live cluster.
# shellcheck source=../../../infra/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../infra/bootstrap/lib.sh"
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need kubectl
need jq
need curl
failed=0
check() { if "$@"; then :; else failed=1; fi; }

apps_ok() {
  local bad
  bad="$(apps_json | jq -r '[.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy") | .metadata.name] | join(" ")')"
  show_apps
  if [[ -z "$bad" ]]; then ok "all Applications Synced and Healthy"; else warn "not Synced/Healthy: $bad"; return 1; fi
}

image_matches_git() {
  local want have
  want="$(awk '/^qops:/{q=1} q && /^    tag:/{print $2; exit}' "$REPO_ROOT/deploy/envs/oci/values.yaml")"
  have="$(k -n qops get cronjob qops-smoke -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')"
  if [[ "$have" == *":$want" ]]; then ok "qops-smoke runs $have (matches deploy/envs/oci)"; else
    warn "qops-smoke runs '$have' but deploy/envs/oci says tag '$want' (pushed yet? Argo syncs within ~3 min)"
    return 1
  fi
}

ui_on_tailnet_only() {
  local tailnet url
  tailnet="$(tofu_output -raw tailnet_dns_name)"
  url="https://argocd.$tailnet/healthz"
  if curl -fsS --max-time 20 "$url" | grep -q ok; then ok "Argo CD UI answers on the tailnet: https://argocd.$tailnet"; else
    warn "Argo CD UI not reachable at $url (the operator's proxy may still be starting)"
    return 1
  fi
  local exposed
  exposed="$(k get svc -A -o json | jq -r '[.items[] | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort") | "\(.metadata.namespace)/\(.metadata.name)"] | join(" ")')"
  if [[ -z "$exposed" ]]; then ok "no LoadBalancer or NodePort services: nothing is exposed outside the tailnet"; else
    warn "services exposed outside the tailnet: $exposed"
    return 1
  fi
}

smoke_runs() {
  local job
  job="qops-smoke-verify-$(date +%s)"
  info "running the smoke job once: $job"
  k -n qops create job "$job" --from=cronjob/qops-smoke >/dev/null
  if k -n qops wait --for=condition=complete "job/$job" --timeout=600s >/dev/null; then
    ok "smoke job completed; last lines:"
    k -n qops logs "job/$job" | tail -n 5 | sed 's/^/     /'
  else
    warn "smoke job didn't complete"
    k -n qops logs "job/$job" --tail=20 2>/dev/null | sed 's/^/     /' || true
    return 1
  fi
}

check apps_ok
check image_matches_git
check ui_on_tailnet_only
check smoke_runs
((failed == 0)) || die "P3 checks failed"
ok "P3 checks passed"

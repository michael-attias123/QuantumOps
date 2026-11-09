#!/usr/bin/env bash
# Offline checks of everything under deploy/ (no cluster needed; runs in CI as "deploy manifests"):
# helm lint, then render each environment and validate every object with kubeconform (incl. Argo CD CRDs).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.local/bin:$PATH"

for c in helm kubeconform uv; do
  command -v "$c" >/dev/null || { echo "error: '$c' is not installed. Run: make tools-admin" >&2; exit 1; }
done

CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
validate() { kubeconform -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS" "$@"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> helm lint"
helm lint --quiet deploy/apps -f deploy/envs/oci/values.yaml
helm lint --quiet deploy/charts/qops

for env in oci ci; do
  echo "==> render + validate env '$env'"
  helm template root deploy/apps -f "deploy/envs/$env/values.yaml" >"$tmp/apps-$env.yaml"
  # The qops chart gets the env file's `qops:` block as its values, exactly as the Application passes it.
  uv run --quiet python -c '
import sys, yaml
env = yaml.safe_load(open(sys.argv[1])) or {}
yaml.safe_dump(env.get("qops") or {}, sys.stdout)' "deploy/envs/$env/values.yaml" >"$tmp/qops-values-$env.yaml"
  helm template qops deploy/charts/qops -f "$tmp/qops-values-$env.yaml" >"$tmp/qops-$env.yaml"
  validate "$tmp/apps-$env.yaml" "$tmp/qops-$env.yaml"
done

echo "==> plain manifests"
validate deploy/bootstrap/root-app.yaml deploy/platform/namespaces deploy/platform/argocd-access

echo "==> every Application points at something that exists"
for env in oci ci; do
  # shellcheck disable=SC2016 # literal "$values/" (Argo CD's ref syntax), not a shell variable
  grep -E '^\s+(path|- \$values/)' "$tmp/apps-$env.yaml" | sed -E 's/.*(path: |\$values\/)//' | while read -r p; do
    [[ -e "$p" ]] || { echo "error: env $env references missing '$p'" >&2; exit 1; }
  done
done
echo "deploy checks passed"

#!/usr/bin/env bash
# Reach the cluster node over Tailscale (no public ports, no SSH keys: Tailscale SSH).
#   Usage: node.sh kubeconfig | ssh [command] | status | verify
#
#   kubeconfig  fetch the k3s kubeconfig -> ~/.kube/qops.yaml, merged into ~/.kube/config as context "qops"
#   ssh         open a shell on the node as 'ubuntu' (sudo works), or run one command
#   status      first-boot progress (cloud-init + /var/log/qops-bootstrap.log)
#   verify      P2 Definition of Done checks that need the live cluster
# shellcheck source=../bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

NODE="${QOPS_NODE:-qops-node-1}"
KUBE_DIR="$HOME/.kube"
QOPS_KUBECONFIG="$KUBE_DIR/qops.yaml"

need jq
need ssh

node_ip() {
  local ts
  ts="$(ts_cmd)"
  [[ -n "$ts" ]] || die "tailscale not found. Run: make tools (or install Tailscale on Windows for WSL)"
  "$ts" status --json 2>/dev/null | jq -r --arg n "$NODE" '
    [.Peer[]? | select(.HostName == $n or (.DNSName // "" | startswith($n + ".")))
      | select(.Online != false) | .TailscaleIPs[]? | select(test("^[0-9.]+$"))] | first // empty'
}

IP="$(node_ip)"
[[ -n "$IP" ]] || die "$NODE isn't on the tailnet (yet). First boot takes ~5 minutes after 'make infra-apply'.
   Still missing after 15 minutes? Check the OCI console: Compute -> Instances -> $NODE -> Console connection."

SSH=(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -o LogLevel=ERROR "ubuntu@$IP")

bootstrapped() { "${SSH[@]}" 'test -f /var/lib/qops-bootstrap.done'; }

fetch_kubeconfig() {
  bootstrapped || die "$NODE is still bootstrapping. Watch it: make node-status"
  local tmp merged
  tmp="$(mktemp)"
  merged="$(mktemp)"
  "${SSH[@]}" 'sudo cat /etc/rancher/k3s/k3s.yaml' >"$tmp"
  # k3s names everything "default" and points at localhost; make it "qops" on the node's tailnet IP.
  sed -i -e "s#https://127.0.0.1:6443#https://$IP:6443#" \
    -e 's/^\(\s*\)name: default$/\1name: qops/' \
    -e 's/^\(\s*\)cluster: default$/\1cluster: qops/' \
    -e 's/^\(\s*\)user: default$/\1user: qops/' \
    -e 's/^current-context: default$/current-context: qops/' "$tmp"
  mkdir -p "$KUBE_DIR"
  chmod 700 "$KUBE_DIR"
  install -m 600 "$tmp" "$QOPS_KUBECONFIG"
  if [[ -f "$KUBE_DIR/config" ]]; then
    KUBECONFIG="$QOPS_KUBECONFIG:$KUBE_DIR/config" kubectl config view --flatten >"$merged"
    install -m 600 "$merged" "$KUBE_DIR/config"
  else
    install -m 600 "$tmp" "$KUBE_DIR/config"
  fi
  rm -f "$tmp" "$merged"
  kubectl config use-context qops >/dev/null
  ok "kubeconfig saved (context 'qops', server https://$IP:6443)"
  kubectl get nodes -o wide
}

verify() {
  local failed=0 nodes
  need kubectl
  nodes="$(kubectl --context qops get nodes -o json)" || die "kubectl can't reach the cluster. Run: make kubeconfig"
  if jq -e '[.items[] | select(.status.nodeInfo.architecture == "arm64")
             | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length == 1' \
    <<<"$nodes" >/dev/null; then
    ok "1 Ready arm64 node"
  else
    warn "expected exactly 1 Ready arm64 node"
    failed=1
  fi
  if jq -e '.items[0].metadata.labels["qops.io/pool"] == "cpu"' <<<"$nodes" >/dev/null; then
    ok "node label qops.io/pool=cpu"
  else
    warn "node label qops.io/pool=cpu missing"
    failed=1
  fi
  if [[ "$("${SSH[@]}" 'tailscale status --self --json' | jq -r '.Self.Tags // [] | join(",")')" == "tag:qops-node" ]]; then
    ok "node joined the tailnet as tag:qops-node"
  else
    warn "node isn't tagged tag:qops-node"
    failed=1
  fi
  return "$failed"
}

CMD="${1:-status}"
shift || true
case "$CMD" in
  kubeconfig) fetch_kubeconfig ;;
  ssh) exec "${SSH[@]}" "$@" ;;
  status)
    "${SSH[@]}" 'cloud-init status || true; echo; tail -n 25 /var/log/qops-bootstrap.log 2>/dev/null || echo "(no bootstrap log yet)"'
    ;;
  verify) verify ;;
  *) die "unknown command: $CMD (kubeconfig | ssh | status | verify)" ;;
esac

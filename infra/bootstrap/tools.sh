#!/usr/bin/env bash
# Install the command-line tools QuantumOps needs on this computer; skip anything already present.
#   Usage: tools.sh [--dry-run] [--admin]
#   --admin also installs OpenTofu and the OCI CLI (needed on the one computer that runs `tofu apply`).
# Supported: Ubuntu/Debian (incl. WSL2) and macOS with Homebrew.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_args "$@"

ADMIN=0
for a in "${ARGS[@]+"${ARGS[@]}"}"; do
  case "$a" in
    --admin) ADMIN=1 ;;
    *) die "unknown argument: $a" ;;
  esac
done

TOFU_MIN="1.10.0"
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) KARCH=amd64 ;;
  aarch64 | arm64) KARCH=arm64 ;;
  *) die "unsupported CPU architecture: $ARCH" ;;
esac

# Run as root. sudo drops environment variables by default, which breaks downloads behind a corporate proxy,
# so the proxy settings are passed through explicitly.
PROXY_VARS="http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY"
as_root() {
  if [[ "$OS" != "Linux" || "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo --preserve-env="$PROXY_VARS" "$@"
  fi
}

# Download an installer to a temp file first (never pipe the network straight into a shell).
fetch() {
  local url="$1" out
  out="$(mktemp)"
  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$out"
  printf '%s\n' "$out"
}

version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

install_base() {
  local missing=()
  local c
  for c in git make curl jq; do have "$c" || missing+=("$c"); done
  if ((${#missing[@]} == 0)); then
    ok "git, make, curl, jq"
    return
  fi
  info "installing ${missing[*]}"
  if [[ "$OS" == "Darwin" ]]; then
    need brew
    run brew install "${missing[@]}"
  else
    run as_root apt-get update -y
    run as_root apt-get install -y "${missing[@]}"
  fi
}

install_uv() {
  if have uv; then
    ok "uv $(uv --version | awk '{print $2}')"
    return
  fi
  info "installing uv"
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run sh "<https://astral.sh/uv/install.sh>"
  else
    sh "$(fetch https://astral.sh/uv/install.sh)"
  fi
  warn "open a new shell (or: source ~/.local/bin/env) so 'uv' is on PATH"
}

install_kubectl() {
  if have kubectl; then
    ok "kubectl $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)"
    return
  fi
  info "installing kubectl"
  if [[ "$OS" == "Darwin" ]]; then
    run brew install kubectl
    return
  fi
  local ver bin
  ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run install kubectl "$ver/$KARCH" /usr/local/bin/kubectl
    return
  fi
  bin="$(fetch "https://dl.k8s.io/release/$ver/bin/linux/$KARCH/kubectl")"
  echo "$(curl -fsSL "https://dl.k8s.io/release/$ver/bin/linux/$KARCH/kubectl.sha256")  $bin" | sha256sum --check --quiet
  as_root install -m 0755 "$bin" /usr/local/bin/kubectl
}

install_tailscale() {
  local ts
  ts="$(ts_cmd)"
  if [[ -n "$ts" ]]; then
    ok "tailscale $("$ts" version | head -n1)"
    return
  fi
  if is_wsl; then
    warn "WSL2: install Tailscale on Windows (https://tailscale.com/download/windows); WSL shares its connection and CLI"
    return
  fi
  info "installing tailscale"
  if [[ "$OS" == "Darwin" ]]; then
    run brew install --cask tailscale
  elif [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run sh "<https://tailscale.com/install.sh>"
  else
    sh "$(fetch https://tailscale.com/install.sh)"
  fi
}

install_tofu() {
  if have tofu; then
    local v
    v="$(tofu version -json 2>/dev/null | jq -r .terraform_version)"
    if version_ge "$v" "$TOFU_MIN"; then
      ok "tofu $v"
      return
    fi
    warn "tofu $v is older than $TOFU_MIN; upgrading"
  fi
  info "installing OpenTofu"
  if [[ "$OS" == "Darwin" ]]; then
    run brew install opentofu
  elif [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run sh "<https://get.opentofu.org/install-opentofu.sh>" --install-method deb
  else
    as_root sh "$(fetch https://get.opentofu.org/install-opentofu.sh)" --install-method deb
  fi
}

# Helm goes into ~/.local/bin (no sudo needed); `make bootstrap` uses it to install Argo CD the first time.
install_helm() {
  if have helm; then
    ok "helm $(helm version --short 2>/dev/null)"
    return
  fi
  info "installing helm"
  if [[ "$OS" == "Darwin" ]]; then
    run brew install helm
    return
  fi
  local ver tgz dir
  ver="$(curl -fsSL https://get.helm.sh/helm-latest-version)"
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run install helm "$ver/$KARCH" "$HOME/.local/bin/helm"
    return
  fi
  tgz="$(fetch "https://get.helm.sh/helm-$ver-linux-$KARCH.tar.gz")"
  echo "$(curl -fsSL "https://get.helm.sh/helm-$ver-linux-$KARCH.tar.gz.sha256sum" | awk '{print $1}')  $tgz" |
    sha256sum --check --quiet
  dir="$(mktemp -d)"
  tar -xzf "$tgz" -C "$dir"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$dir/linux-$KARCH/helm" "$HOME/.local/bin/helm"
  rm -rf "$dir" "$tgz"
  have helm || warn "add ~/.local/bin to PATH (open a new shell) so 'helm' is found"
}

# kubeconform validates rendered manifests (`make deploy-check`). Pinned; into ~/.local/bin.
KUBECONFORM_VERSION="v0.7.0"
install_kubeconform() {
  if have kubeconform; then
    ok "kubeconform $(kubeconform -v 2>/dev/null)"
    return
  fi
  info "installing kubeconform $KUBECONFORM_VERSION"
  if [[ "$OS" == "Darwin" ]]; then
    run brew install kubeconform
    return
  fi
  local base="https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION" name tgz dir
  name="kubeconform-linux-$KARCH.tar.gz"
  if [[ "$QOPS_DRY_RUN" == "1" ]]; then
    run install kubeconform "$KUBECONFORM_VERSION/$KARCH" "$HOME/.local/bin/kubeconform"
    return
  fi
  tgz="$(fetch "$base/$name")"
  echo "$(curl -fsSL "$base/CHECKSUMS" | awk -v n="$name" '$2 == n {print $1}')  $tgz" | sha256sum --check --quiet
  dir="$(mktemp -d)"
  tar -xzf "$tgz" -C "$dir"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$dir/kubeconform" "$HOME/.local/bin/kubeconform"
  rm -rf "$dir" "$tgz"
}

install_oci_cli() {
  if have oci; then
    ok "oci $(oci --version)"
    return
  fi
  info "installing the OCI CLI (as a uv tool)"
  need uv
  run uv tool install oci-cli
}

ssh_key() {
  local key="$HOME/.ssh/qops_oci"
  if [[ -f "$key" ]]; then
    ok "SSH break-glass key $key"
    return
  fi
  info "creating SSH break-glass key $key"
  run mkdir -p "$HOME/.ssh"
  run ssh-keygen -q -t ed25519 -N "" -C qops-oci -f "$key"
}

info "QuantumOps tools for $(os_name) ($KARCH)$([[ $ADMIN == 1 ]] && echo ', admin computer')"
install_base
install_uv
install_kubectl
install_tailscale
if [[ "$ADMIN" == "1" ]]; then
  install_tofu
  install_helm
  install_kubeconform
  install_oci_cli
  ssh_key
fi
info "done. Next: 'tailscale up' (browser login), then on the admin computer: make oci-login"

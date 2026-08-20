# shellcheck shell=bash
# Module: Cloud development tools — k3s (lightweight Kubernetes, bundles
# kubectl), Helm, k9s, Ansible, and the AWS CLI. k3s and Helm install via
# their official scripts, each resolving the latest stable release; k9s
# comes from its official GitHub releases (latest resolved at run time;
# K9S_VERSION in versions.env is the offline fallback); Ansible installs
# the latest community package from PyPI via pipx, the method its docs
# recommend; the AWS CLI v2 bundle URL always serves the latest release.

module_cloud_describe() { echo "Cloud dev tools (k3s + kubectl, Helm, k9s, Ansible, AWS CLI — latest stable)"; }

module_cloud_install() {
  section "Cloud development tools"

  # --- k3s (bundles kubectl/crictl/ctr as symlinks) --------------------------
  log "Installing k3s (latest stable channel) via the official script..."
  if [[ -d /run/systemd/system ]]; then
    fetch https://get.k3s.io | sudo sh -
  else
    # Containers (e.g. the test suite) have no systemd: install the binary
    # but skip service enable/start — harmless on a real machine, honest in CI.
    warn "No systemd detected: installing k3s without enabling/starting the service."
    fetch https://get.k3s.io | sudo INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_SKIP_START=true sh -
  fi
  ok "k3s: $(k3s --version | head -n1)"

  # --- Helm ------------------------------------------------------------------
  log "Installing Helm (latest stable) via the official get-helm-4 script..."
  fetch https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
  ok "Helm: $(helm version --short)"

  # --- k9s -------------------------------------------------------------------
  local k9s_ver
  k9s_ver="$(fetch https://api.github.com/repos/derailed/k9s/releases/latest 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -n1 | sed 's/.*"\(v[^"]*\)"/\1/')" || true
  if [[ -z "$k9s_ver" ]]; then
    warn "Could not resolve the latest k9s release from the GitHub API; using pinned ${K9S_VERSION}."
    k9s_ver="$K9S_VERSION"
  fi
  local tmp; tmp="$(mktemp -d)"
  fetch "https://github.com/derailed/k9s/releases/download/${k9s_ver}/k9s_linux_amd64.deb" \
    -o "${tmp}/k9s.deb"
  apt_install "${tmp}/k9s.deb"
  ok "k9s: $(k9s version --short 2>/dev/null | head -n1 || k9s version | head -n1)"

  # --- Ansible ---------------------------------------------------------------
  log "Installing Ansible (latest community release from PyPI, via pipx)..."
  command_exists pipx || apt_install pipx
  if pipx list --short 2>/dev/null | grep -q '^ansible '; then
    pipx upgrade --include-injected ansible >/dev/null
  else
    pipx install --include-deps ansible >/dev/null
  fi
  pipx ensurepath >/dev/null 2>&1
  ok "Ansible: $("$HOME/.local/bin/ansible" --version 2>/dev/null | head -n1 || ansible --version | head -n1)"

  # --- AWS CLI v2 ------------------------------------------------------------
  # The official bundle URL always serves the latest v2 release; --update
  # makes re-runs an in-place upgrade.
  log "Installing AWS CLI v2 (latest) from the official bundle..."
  command_exists unzip || apt_install unzip
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${tmp}/awscliv2.zip"
  ( cd "$tmp" && unzip -q awscliv2.zip && sudo ./aws/install --update )
  rm -rf "$tmp"
  ok "AWS CLI: $(aws --version 2>&1 | head -n1)"

  log "k3s cluster access needs root by default: 'sudo k3s kubectl get nodes'."
  log "For your user: sudo chmod 644 /etc/rancher/k3s/k3s.yaml (or set KUBECONFIG from a copy)."
}

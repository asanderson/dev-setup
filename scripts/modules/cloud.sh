# shellcheck shell=bash
# Module: Cloud development tools — k3s (lightweight Kubernetes, bundles
# kubectl), Helm, k9s, Ansible, and the AWS CLI. k3s and Helm install via
# their official scripts, each resolving the latest stable release; k9s
# comes from its official GitHub releases (latest resolved at run time,
# .deb or .rpm per target family; K9S_VERSION in versions.env is the
# offline fallback); Ansible installs the latest community package from
# PyPI via pipx, the method its docs recommend; the AWS CLI v2 bundle URL
# always serves the latest release. Works on every target OS.

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
  if [[ "$(os_family)" == deb ]]; then
    fetch_deb_install "https://github.com/derailed/k9s/releases/download/${k9s_ver}/k9s_linux_amd64.deb"
  else
    fetch_rpm_install "https://github.com/derailed/k9s/releases/download/${k9s_ver}/k9s_linux_amd64.rpm"
  fi
  ok "k9s: $(k9s version --short 2>/dev/null | head -n1 || k9s version | head -n1)"

  # --- Ansible ---------------------------------------------------------------
  log "Installing Ansible (latest community release from PyPI, via pipx)..."
  if ! command_exists pipx; then
    if [[ "$(os_family)" == deb ]]; then
      apt_install pipx
    else
      sudo dnf install -y python3-pip
      python3 -m pip install --user --quiet pipx
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
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
  if ! command_exists unzip; then
    if [[ "$(os_family)" == deb ]]; then apt_install unzip; else sudo dnf install -y unzip; fi
  fi
  local tmp; tmp="$(mktemp -d)"
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${tmp}/awscliv2.zip"
  ( cd "$tmp" && unzip -q awscliv2.zip && sudo ./aws/install --update )
  rm -rf "$tmp"
  ok "AWS CLI: $(aws --version 2>&1 | head -n1)"

  log "k3s cluster access needs root by default: 'sudo k3s kubectl get nodes'."
  log "For your user: sudo chmod 644 /etc/rancher/k3s/k3s.yaml (or set KUBECONFIG from a copy)."
}

module_cloud_uninstall() {
  section "Uninstall: Cloud development tools"
  if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    sudo /usr/local/bin/k3s-uninstall.sh >/dev/null 2>&1 || true
    log "k3s removed via its own uninstaller."
  else
    sudo rm -f /usr/local/bin/k3s
  fi
  sudo rm -f /usr/local/bin/helm
  pkg_remove k9s
  command_exists pipx && pipx uninstall ansible >/dev/null 2>&1 || true
  sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.kube" "$HOME/.aws" "$HOME/.ansible"
    log "Purged ~/.kube, ~/.aws, ~/.ansible."
  else
    log "Kept: ~/.kube, ~/.aws, ~/.ansible (--purge-data removes them)."
  fi
}

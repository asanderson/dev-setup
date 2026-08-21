# shellcheck shell=bash
# Module: Python toolchain — the distro's default Python 3 with venv, pip,
# dev headers, and pipx for isolated CLI tools, on every target OS (apt or
# dnf). Per-project interpreters/deps belong in venvs, not system pip.

module_python_describe() { echo "Python 3 (venv, pip, dev headers, pipx)"; }

module_python_install() {
  section "Python 3 toolchain"
  if [[ "$(os_family)" == deb ]]; then
    apt_install python3 python3-venv python3-pip python3-dev pipx
  else
    sudo dnf install -y python3 python3-pip python3-devel
    # pipx: EL packages it in EPEL, not BaseOS/AppStream — pip --user is the
    # dependable path everywhere.
    command_exists pipx || python3 -m pip install --user --quiet pipx
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # Put pipx-installed CLI tools (~/.local/bin) on PATH for future shells;
  # idempotent — pipx skips shells it already configured.
  pipx ensurepath >/dev/null 2>&1

  ok "Python: $(python3 --version)"
  ok "pip:    $(pip3 --version)"
  log "Use 'python3 -m venv' for project environments and 'pipx install' for CLI tools."
}

module_python_uninstall() {
  section "Uninstall: Python extras"
  # python3 itself is never removed — the OS depends on it. Only the dev
  # extras this module added go.
  if [[ "$(os_family)" == deb ]]; then
    sudo apt-get remove -y python3-venv python3-pip python3-dev pipx 2>/dev/null || true
  else
    sudo dnf remove -y python3-pip python3-devel 2>/dev/null || true
    rm -f "$HOME/.local/bin/pipx"
  fi
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.local/pipx"
    log "Purged ~/.local/pipx (pipx-installed tools)."
  else
    log "Kept: python3 (OS dependency) and ~/.local/pipx (--purge-data removes the latter)."
  fi
}

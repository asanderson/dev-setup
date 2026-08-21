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

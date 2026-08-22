# shellcheck shell=bash
# Module: Python toolchain — the distro's default Python 3 with venv, pip,
# dev headers, pipx for isolated CLI tools, and uv (Astral's fast package
# and project manager, official installer, latest) on every target OS
# (apt or dnf). Per-project interpreters/deps belong in venvs, not
# system pip.

module_python_describe() { echo "Python 3 (venv, pip, dev headers, pipx, uv)"; }

module_python_install() {
  section "Python 3 toolchain"
  if [[ "$(os_family)" == deb ]]; then
    apt_install python3 python3-venv python3-pip python3-dev
    # pipx entered the Debian archive at bookworm — older derivatives
    # (e.g. PureOS byzantium) fall back to pip --user.
    apt_install pipx 2>/dev/null \
      || { command_exists pipx || python3 -m pip install --user --quiet pipx; }
    export PATH="$HOME/.local/bin:$PATH"
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

  # uv — Astral's fast package/project manager (official installer,
  # latest release, per-user under ~/.local/bin).
  fetch https://astral.sh/uv/install.sh | sh >/dev/null
  ok "Python: $(python3 --version)"
  ok "pip:    $(pip3 --version)"
  ok "uv:     $("$HOME/.local/bin/uv" --version)"
  log "Use 'python3 -m venv' or 'uv venv' for project environments and"
  log "'pipx install' (or 'uv tool install') for CLI tools."
}

module_python_uninstall() {
  section "Uninstall: Python extras"
  # python3 itself is never removed — the OS depends on it. Only the dev
  # extras this module added go.
  pkg_remove python3-venv python3-pip python3-dev python3-devel pipx
  rm -f "$HOME/.local/bin/pipx" "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.local/pipx" "$HOME/.local/share/uv" "$HOME/.cache/uv"
    log "Purged ~/.local/pipx (pipx-installed tools) and uv's tool/cache dirs."
  else
    log "Kept: python3 (OS dependency) and ~/.local/pipx (--purge-data removes the latter)."
  fi
}

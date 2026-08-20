# shellcheck shell=bash
# Module: Visual Studio Code — Microsoft's official apt repository, stable
# channel. The 'code' package auto-updates through apt thereafter.
# https://code.visualstudio.com/docs/setup/linux

module_vscode_describe() { echo "Visual Studio Code (Microsoft apt repo, stable)"; }

module_vscode_install() {
  section "Visual Studio Code"

  add_apt_repo vscode \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main"
  apt_install code

  ok "Installed: $(code --version 2>/dev/null | head -n1 || echo 'code (version check needs a non-root shell)')"
  log "Launch with 'code'; extensions install per-user on first run."
}

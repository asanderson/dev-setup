# shellcheck shell=bash
# Module: LibreOffice — The Document Foundation's office suite (Writer,
# Calc, Impress, Draw, Base, Math) from the distro archive on every target
# OS: apt on the Debian family, AppStream via dnf on Enterprise Linux.
# Security updates arrive with the rest of the system.
# https://www.libreoffice.org

module_libreoffice_describe() { echo "LibreOffice (office suite, distro packages)"; }

module_libreoffice_install() {
  section "LibreOffice"
  if [[ "$(os_family)" == deb ]]; then
    apt_install libreoffice
  else
    sudo dnf install -y libreoffice
  fi
  ok "Installed: $(libreoffice --version 2>/dev/null | head -n1 || echo libreoffice)"
}

module_libreoffice_uninstall() {
  section "Uninstall: LibreOffice"
  if command_exists dpkg; then
    local -a pkgs
    mapfile -t pkgs < <(dpkg-query -W -f='${Package}\n' 'libreoffice*' 2>/dev/null)
    pkg_remove "${pkgs[@]}"
  else
    local -a pkgs
    mapfile -t pkgs < <(rpm -qa --qf '%{NAME}\n' 'libreoffice*' 2>/dev/null)
    pkg_remove "${pkgs[@]}"
  fi
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.config/libreoffice"
    log "Purged ~/.config/libreoffice (profile, settings, recent files)."
  else
    log "Kept: ~/.config/libreoffice (user profile — --purge-data removes it). Documents are never touched."
  fi
}

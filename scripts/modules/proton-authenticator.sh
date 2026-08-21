# shellcheck shell=bash
# Module: Proton Authenticator — the TOTP two-factor app (Linux app since
# 2025), from Proton's stable latest-version .deb URL (no apt repo; the app
# self-checks for updates).

module_proton_authenticator_describe() { echo "Proton Authenticator (official package, latest)"; }

module_proton_authenticator_install() {
  section "Proton Authenticator"
  fetch_pkg_install \
    "https://proton.me/download/authenticator/linux/ProtonAuthenticator.deb" \
    "https://proton.me/download/authenticator/linux/ProtonAuthenticator.rpm"
  ok "Installed: proton-authenticator $(command -v dpkg-query >/dev/null && dpkg-query -W -f='${Version}' proton-authenticator 2>/dev/null || rpm -q --qf '%{VERSION}' proton-authenticator 2>/dev/null || true)"
}

module_proton_authenticator_uninstall() {
  section "Uninstall: Proton Authenticator"
  if [[ "$(os_family)" == deb ]]; then
    sudo apt-get remove -y proton-authenticator 2>/dev/null || true
  else
    sudo dnf remove -y proton-authenticator 2>/dev/null || true
  fi
}

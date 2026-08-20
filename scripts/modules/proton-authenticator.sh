# shellcheck shell=bash
# Module: Proton Authenticator — the TOTP two-factor app (Linux app since
# 2025), from Proton's stable latest-version .deb URL (no apt repo; the app
# self-checks for updates).

module_proton_authenticator_describe() { echo "Proton Authenticator (official .deb, latest)"; }

module_proton_authenticator_install() {
  section "Proton Authenticator"
  fetch_deb_install "https://proton.me/download/authenticator/linux/ProtonAuthenticator.deb"
  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' proton-authenticator)"
}

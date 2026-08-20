# shellcheck shell=bash
# Module: Proton Pass — the password manager's official Linux desktop app,
# from Proton's stable latest-version .deb URL (no apt repo; the app
# self-checks for updates).

module_proton_pass_describe() { echo "Proton Pass (official .deb, latest)"; }

module_proton_pass_install() {
  section "Proton Pass"
  fetch_deb_install "https://proton.me/download/PassDesktop/linux/x64/ProtonPass.deb"
  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' proton-pass)"
}

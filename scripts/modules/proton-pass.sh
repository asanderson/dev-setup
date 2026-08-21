# shellcheck shell=bash
# Module: Proton Pass — the password manager's official Linux desktop app,
# from Proton's stable latest-version .deb URL (no apt repo; the app
# self-checks for updates).

module_proton_pass_describe() { echo "Proton Pass (official package, latest)"; }

module_proton_pass_install() {
  section "Proton Pass"
  fetch_pkg_install \
    "https://proton.me/download/PassDesktop/linux/x64/ProtonPass.deb" \
    "https://proton.me/download/PassDesktop/linux/x64/ProtonPass.rpm"
  ok "Installed: proton-pass $(command -v dpkg-query >/dev/null && dpkg-query -W -f='${Version}' proton-pass 2>/dev/null || rpm -q --qf '%{VERSION}' proton-pass 2>/dev/null || true)"
}

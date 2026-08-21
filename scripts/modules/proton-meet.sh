# shellcheck shell=bash
# Module: Proton Meet — the end-to-end-encrypted videoconferencing desktop
# app (launched 2026), from Proton's stable latest-version .deb URL (no apt
# repo; the app self-checks for updates; web: meet.proton.me).

module_proton_meet_describe() { echo "Proton Meet (official package, latest)"; }

module_proton_meet_install() {
  section "Proton Meet"
  fetch_pkg_install \
    "https://proton.me/download/meet/linux/ProtonMeet-desktop.deb" \
    "https://proton.me/download/meet/linux/ProtonMeet-desktop.rpm"
  ok "Installed: proton-meet $(command -v dpkg-query >/dev/null && dpkg-query -W -f='${Version}' proton-meet 2>/dev/null || rpm -q --qf '%{VERSION}' proton-meet 2>/dev/null || true)"
}

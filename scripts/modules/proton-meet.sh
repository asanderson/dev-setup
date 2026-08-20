# shellcheck shell=bash
# Module: Proton Meet — the end-to-end-encrypted videoconferencing desktop
# app (launched 2026), from Proton's stable latest-version .deb URL (no apt
# repo; the app self-checks for updates; web: meet.proton.me).

module_proton_meet_describe() { echo "Proton Meet (official .deb, latest)"; }

module_proton_meet_install() {
  section "Proton Meet"
  fetch_deb_install "https://proton.me/download/meet/linux/ProtonMeet-desktop.deb"
  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' proton-meet)"
}

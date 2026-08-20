# shellcheck shell=bash
# Module: Proton Mail desktop — official .deb from Proton's stable
# latest-version URL (no apt repo exists for it; the app checks for its own
# updates). Bundles Proton Calendar, which has no standalone Linux app.

module_proton_mail_describe() { echo "Proton Mail desktop (official .deb, latest — bundles Proton Calendar)"; }

module_proton_mail_install() {
  section "Proton Mail desktop"
  fetch_deb_install "https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb"
  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' proton-mail)"
  log "Proton Calendar is bundled in this app (no standalone Linux app exists;"
  log "web: calendar.proton.me). The app self-checks for updates — no apt repo."
}

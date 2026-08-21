# shellcheck shell=bash
# Module: Proton Mail desktop — official .deb from Proton's stable
# latest-version URL (no apt repo exists for it; the app checks for its own
# updates). Bundles Proton Calendar, which has no standalone Linux app.

module_proton_mail_describe() { echo "Proton Mail desktop (official package, latest — bundles Proton Calendar)"; }

module_proton_mail_install() {
  section "Proton Mail desktop"
  fetch_pkg_install \
    "https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb" \
    "https://proton.me/download/mail/linux/ProtonMail-desktop-beta.rpm"
  ok "Installed: proton-mail $(command -v dpkg-query >/dev/null && dpkg-query -W -f='${Version}' proton-mail 2>/dev/null || rpm -q --qf '%{VERSION}' proton-mail 2>/dev/null || true)"
  log "Proton Calendar is bundled in this app (no standalone Linux app exists;"
  log "web: calendar.proton.me). The app self-checks for updates — no apt repo."
}

module_proton_mail_uninstall() {
  section "Uninstall: Proton Mail desktop"
  pkg_remove proton-mail
}

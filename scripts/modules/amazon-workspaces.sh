# shellcheck shell=bash
# Module: Amazon WorkSpaces client — AWS's official Linux client
# (workspacesclient, DCV and WSP streaming) from Amazon's apt repository.
# Amazon publishes suites for the Ubuntu LTS releases it supports (focal,
# jammy, noble). A release without its own suite is refused with guidance
# instead of borrowing an older one: the noble build depends on libraries
# a newer release no longer ships (libicu74, libxml2 on 26.04), so it
# cannot install there. No Debian or Enterprise Linux client exists.
# https://clients.amazonworkspaces.com/linux-install

module_amazon_workspaces_describe() { echo "Amazon WorkSpaces client (Amazon's apt repo)"; }

module_amazon_workspaces_install() {
  section "Amazon WorkSpaces client"
  local repo="https://d3nt0h4h6pmmc4.cloudfront.net/ubuntu" suite
  # shellcheck disable=SC1091
  . /etc/os-release
  suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  if ! fetch --head "${repo}/dists/${suite}/Release" >/dev/null 2>&1; then
    err "Amazon publishes no WorkSpaces client for Ubuntu ${VERSION_ID:-} (${suite}) yet — its newest build"
    err "(noble, 24.04) depends on libraries this release no longer ships, so it cannot install here."
    err "Meanwhile use WorkSpaces Web Access (https://clients.amazonworkspaces.com/webaccess) or the"
    err "Windows client (scripts/setup.ps1 --amazon-workspaces); re-run once Amazon adds a '${suite}' suite."
    return 1
  fi
  add_apt_repo amazon-workspaces-clients \
    "https://workspaces-client-linux-public-key.s3-us-west-2.amazonaws.com/ADB332E7.asc" \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/amazon-workspaces-clients.gpg] ${repo} ${suite} main"
  apt_install workspacesclient
  ok "Installed: workspacesclient $(dpkg-query -W -f='${Version}' workspacesclient 2>/dev/null || true)"
  log "Launch 'Amazon WorkSpaces' from the app menu and enter your registration code."
}

module_amazon_workspaces_uninstall() {
  section "Uninstall: Amazon WorkSpaces client"
  pkg_remove workspacesclient
  sudo rm -f /etc/apt/sources.list.d/amazon-workspaces-clients.list /etc/apt/keyrings/amazon-workspaces-clients.gpg
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.local/share/Amazon Web Services" "$HOME/.config/Amazon Web Services"
    log "Purged the client's saved registrations and settings."
  else
    log "Kept: saved registration codes and settings (--purge-data removes them)."
  fi
}

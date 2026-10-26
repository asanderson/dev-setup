# shellcheck shell=bash
# Module: Amazon WorkSpaces client — AWS's official Linux client
# (workspacesclient, DCV and WSP streaming) from Amazon's apt repository.
# Amazon publishes suites for Ubuntu LTS releases only (focal, jammy,
# noble); a newer Ubuntu without its own suite yet uses the newest one
# (noble), which is not yet on Amazon's supported list — the module says
# so. No Debian or Enterprise Linux client exists.
# https://clients.amazonworkspaces.com/linux-install

module_amazon_workspaces_describe() { echo "Amazon WorkSpaces client (Amazon's apt repo)"; }

module_amazon_workspaces_install() {
  section "Amazon WorkSpaces client"
  local repo="https://d3nt0h4h6pmmc4.cloudfront.net/ubuntu" suite
  # shellcheck disable=SC1091
  . /etc/os-release
  suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  if ! fetch --head "${repo}/dists/${suite}/Release" >/dev/null 2>&1; then
    warn "Amazon publishes no WorkSpaces suite for '${suite}' yet; using 'noble' (Ubuntu 24.04 — not officially supported on this release)."
    suite="noble"
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

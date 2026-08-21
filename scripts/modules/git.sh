# shellcheck shell=bash
# Module: Git — every target OS: the git-core PPA offers the newest Git on
# Ubuntu; Debian/PureOS install from their archives; Enterprise Linux via
# dnf. git-lfs everywhere.

module_git_describe() { echo "Git (latest stable; git-core PPA on Ubuntu, distro package elsewhere)"; }

module_git_install() {
  section "Git"
  if [[ "$(os_family)" == deb ]]; then
    # The PPA is an Ubuntu channel — never offered on Debian/PureOS.
    if [[ "${TARGET_OS:-ubuntu}" == "ubuntu" ]] \
        && confirm "Use the git-core PPA for the newest Git (recommended)?" y; then
      apt_install software-properties-common
      sudo add-apt-repository -y ppa:git-core/ppa
      _APT_UPDATED=""
    fi
    apt_install git git-lfs
  else
    sudo dnf install -y git git-lfs
  fi
  git lfs install --skip-repo

  ok "Installed: $(git --version)"

  if [[ -z "$(git config --global user.name || true)" ]]; then
    if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
      log "DEV_SETUP_ASSUME_YES=1 — skipping git identity setup (run 'git config --global user.name/user.email' later)."
    elif confirm "Configure git user.name / user.email now?" y; then
      local name email
      read -r -p "  git user.name: " name
      read -r -p "  git user.email: " email
      [[ -n "$name" ]] && git config --global user.name "$name"
      [[ -n "$email" ]] && git config --global user.email "$email"
    fi
  fi
  git config --global init.defaultBranch main
}

module_git_uninstall() {
  section "Uninstall: Git"
  if [[ "$(os_family)" == deb ]]; then
    sudo apt-get remove -y git git-lfs || true
    sudo rm -f /etc/apt/sources.list.d/git-core-*.list /etc/apt/sources.list.d/git-core-*.sources
  else
    sudo dnf remove -y git git-lfs || true
  fi
  log "Kept: your global git config (~/.gitconfig) and repositories."
}

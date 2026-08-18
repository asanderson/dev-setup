# shellcheck shell=bash
# Module: Git — latest stable via the git-core PPA (falls back to Ubuntu archive).

module_git_describe() { echo "Git (latest stable, git-core PPA)"; }

module_git_install() {
  section "Git"
  if confirm "Use the git-core PPA for the newest Git (recommended)?" y; then
    apt_install software-properties-common
    sudo add-apt-repository -y ppa:git-core/ppa
    _APT_UPDATED=""
  fi
  apt_install git git-lfs
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

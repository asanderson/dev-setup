# shellcheck shell=bash
# Module: Node.js toolchain — nvm (Node Version Manager, latest release)
# installs and manages Node itself: the latest LTS line with bundled npm
# lands via `nvm install --lts`, per-user under ~/.nvm, identically on
# every target OS with no vendor packages. yarn + pnpm arrive as corepack
# shims where Node bundles corepack, and Bun (official installer, latest)
# rounds it out. Claude Code's JS tooling — plugins, skills, MCP servers —
# runs on these.
# https://github.com/nvm-sh/nvm   https://bun.sh

module_nodejs_describe() { echo "Node.js via nvm (LTS + npm), corepack (yarn/pnpm), Bun (Claude Code's JS tooling)"; }

module_nodejs_install() {
  section "Node.js toolchain"

  # nvm — latest release resolved from GitHub's releases redirect;
  # NVM_VERSION in versions.env is the offline fallback.
  # `|| true` inside the substitution: under pipefail+errexit a failing
  # curl would otherwise kill the module at this assignment, silently,
  # before the fallback below can engage.
  local nvm_tag
  nvm_tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/nvm-sh/nvm/releases/latest 2>/dev/null | sed 's|.*/||' || true)"
  [[ "$nvm_tag" =~ ^v[0-9] ]] || nvm_tag="$NVM_VERSION"
  fetch "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_tag}/install.sh" | bash >/dev/null
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  ok "nvm:  $(nvm --version) (${nvm_tag})"

  # The nvm installer wires interactive shells (~/.bashrc); non-interactive
  # login shells (bash -lc, scripts, containers) stop at the interactive
  # guard before those lines, so wire the login-shell files too.
  local rc
  for rc in "$HOME/.profile" "$HOME/.bash_profile"; do
    [[ -e "$rc" || "$rc" == "$HOME/.profile" ]] || continue
    if ! grep -q 'NVM_DIR/nvm.sh' "$rc" 2>/dev/null; then
      printf '\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n' >>"$rc"
    fi
  done

  # Node: latest LTS with bundled npm, set as the default.
  nvm install --lts >/dev/null
  nvm alias default 'lts/*' >/dev/null
  ok "Node: $(node --version)   npm: $(npm --version)"

  # yarn + pnpm arrive as corepack shims — inside nvm's user-owned Node,
  # so no sudo is involved (guarded: newer Node lines plan to drop
  # corepack from the dist).
  if command -v corepack >/dev/null 2>&1; then
    corepack enable
    ok "corepack enabled: yarn and pnpm shims are on PATH."
  else
    log "corepack not bundled with this Node build — 'npm install -g yarn pnpm' when needed."
  fi

  # Bun — official installer, latest release, per-user under ~/.bun.
  if [[ "$(os_family)" == deb ]]; then apt_install unzip; else sudo dnf install -y unzip; fi
  fetch https://bun.sh/install | bash >/dev/null
  ok "Bun:  $("$HOME/.bun/bin/bun" --version)"
  log "New shells pick everything up from ~/.nvm and ~/.bun (shell rc wired)."
  log "Per-project Node versions: 'nvm install <ver>' + an .nvmrc in the project."
}

module_nodejs_uninstall() {
  section "Uninstall: Node.js toolchain"
  # nvm holds the managed Node versions inside ~/.nvm — removing it
  # removes them (project node_modules elsewhere are untouched).
  rm -rf "$HOME/.nvm" "$HOME/.bun"
  sed -i '/NVM_DIR/d' "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" 2>/dev/null || true
  log "Removed nvm (~/.nvm, managed Node versions included) and Bun (~/.bun)."
  # Earlier revisions of this module installed NodeSource system packages —
  # clean those up too if present.
  sudo corepack disable >/dev/null 2>&1 || true
  pkg_remove nodejs
  sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg \
    /etc/yum.repos.d/nodesource-nodejs.repo
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.npm" "$HOME/.cache/yarn" "$HOME/.local/share/pnpm"
    log "Purged npm/yarn/pnpm caches and stores."
  else
    log "Kept: ~/.npm cache (+ yarn/pnpm stores — --purge-data removes them)."
  fi
}

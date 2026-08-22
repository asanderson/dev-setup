# shellcheck shell=bash
# Module: Node.js toolchain — the latest LTS Node.js (with npm) from
# NodeSource's distro-agnostic repos (the deb "nodistro" suite / rpm
# nodistro tree, so every target family gets the same current line),
# yarn + pnpm via corepack where Node bundles it, and Bun (official
# installer, latest release). Claude Code's JS tooling — plugins, skills,
# MCP servers — runs on these.
# https://github.com/nodesource/distributions   https://bun.sh

module_nodejs_describe() { echo "Node.js LTS + npm, corepack (yarn/pnpm), Bun (Claude Code's JS tooling)"; }

module_nodejs_install() {
  section "Node.js toolchain"
  if [[ "$(os_family)" == deb ]]; then
    add_apt_repo nodesource \
      "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
      "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main"
    apt_install nodejs
  else
    sudo tee /etc/yum.repos.d/nodesource-nodejs.repo >/dev/null <<EOF
[nodesource-nodejs]
name=Node.js ${NODE_MAJOR}.x
baseurl=https://rpm.nodesource.com/pub_${NODE_MAJOR}.x/nodistro/nodejs/x86_64
enabled=1
gpgcheck=1
gpgkey=https://rpm.nodesource.com/gpgkey/ns-operations-public.key
EOF
    sudo dnf install -y nodejs
  fi
  ok "Node: $(node --version)   npm: $(npm --version)"

  # yarn + pnpm arrive as corepack shims — bundled with Node on the LTS
  # line (guarded: newer Node lines plan to drop corepack from the dist).
  if command_exists corepack; then
    sudo corepack enable
    ok "corepack enabled: yarn and pnpm shims are on PATH."
  else
    log "corepack not bundled with this Node build — 'npm install -g yarn pnpm' when needed."
  fi

  # Bun — official installer, latest release, per-user under ~/.bun.
  if [[ "$(os_family)" == deb ]]; then apt_install unzip; else sudo dnf install -y unzip; fi
  fetch https://bun.sh/install | bash >/dev/null
  ok "Bun:  $("$HOME/.bun/bin/bun" --version)"
  log "New shells pick Bun up from ~/.bun/bin (the installer wires the shell rc)."
}

module_nodejs_uninstall() {
  section "Uninstall: Node.js toolchain"
  sudo corepack disable >/dev/null 2>&1 || true
  pkg_remove nodejs
  sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg \
    /etc/yum.repos.d/nodesource-nodejs.repo
  rm -rf "$HOME/.bun"
  log "Removed Bun (~/.bun)."
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.npm" "$HOME/.cache/yarn" "$HOME/.local/share/pnpm"
    log "Purged npm/yarn/pnpm caches and stores."
  else
    log "Kept: ~/.npm cache (+ yarn/pnpm stores — --purge-data removes them)."
  fi
}

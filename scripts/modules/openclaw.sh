# shellcheck shell=bash
# Module: OpenClaw — the self-hosted personal AI assistant gateway, via its
# official install script using the npm method (latest), into the nodejs
# module's nvm-managed Node (the installer reuses nvm when present).
# Onboarding is left to you: `openclaw onboard --install-daemon` sets up
# the gateway service, channels and model access.
# https://github.com/openclaw/openclaw

module_openclaw_describe() { echo "OpenClaw (self-hosted AI assistant gateway, official installer, latest)"; }

module_openclaw_install() {
  section "OpenClaw"
  require_nvm_node openclaw
  fetch https://openclaw.ai/install.sh | bash -s -- --install-method npm --no-onboard --no-prompt
  ok "Installed: $(openclaw --version 2>/dev/null || echo openclaw)"
  log "Next: 'openclaw onboard --install-daemon', then 'openclaw security audit --deep'."
  warn "OpenClaw runs tools on this host with no sandbox by default and trusts its plugins fully:"
  warn "keep the gateway on loopback (SSH tunnel/Tailscale for remote use), treat inbound"
  warn "messages and model output as untrusted, and use a dedicated user or VM for shared setups."
}

module_openclaw_uninstall() {
  section "Uninstall: OpenClaw"
  if require_nvm_node openclaw 2>/dev/null && command_exists openclaw; then
    if [[ "${PURGE_DATA:-0}" == "1" ]]; then
      # --state removes ~/.openclaw (the default workspace lives inside it);
      # not --all, whose --workspace scope deletes configured workspace
      # directories wherever they are — user project dirs included.
      openclaw uninstall --service --state --yes --non-interactive || true
      log "Removed the gateway service and ~/.openclaw state (workspaces configured elsewhere are kept)."
    else
      openclaw uninstall --service --yes --non-interactive || true
      log "Kept: ~/.openclaw (config, credentials, workspace — --purge-data removes it)."
    fi
    npm rm -g openclaw >/dev/null 2>&1 || true
  else
    log "OpenClaw CLI not found — nothing to remove."
  fi
}

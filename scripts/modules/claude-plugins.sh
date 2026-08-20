# shellcheck shell=bash
# Module: Claude Code plugins — a curated marketplace + plugin set, installed
# via the claude CLI (works headless; plugin management needs no login).
# Each entry: "<github-repo> <plugin>@<marketplace-name>", the marketplace
# name taken from the repo's .claude-plugin/marketplace.json. Re-runs
# re-add marketplaces harmlessly and keep plugins at their latest release.

CLAUDE_PLUGINS=(
  "obra/superpowers superpowers@superpowers-dev"
  "juliusbrussee/caveman caveman@caveman"
  "multica-ai/andrej-karpathy-skills andrej-karpathy-skills@karpathy-skills"
  "affaan-m/ecc ecc@ecc"
  "thedotmack/claude-mem claude-mem@thedotmack"
  "sickn33/agentic-awesome-skills agentic-awesome-skills@agentic-awesome-skills"
  "open-gsd/gsd-core gsd-core@gsd-core"
)

module_claude_plugins_describe() { echo "Claude Code plugins (superpowers, caveman, karpathy-skills, ecc, claude-mem, agentic-awesome-skills, gsd-core)"; }

module_claude_plugins_install() {
  section "Claude Code plugins"

  local claude="$HOME/.local/bin/claude"
  command_exists claude && claude="$(command -v claude)"
  if [[ ! -x "$claude" ]]; then
    err "Claude Code not found. Select the Claude Code module first."
    return 1
  fi
  # Marketplace add clones the repo with git.
  command_exists git || apt_install git

  local spec repo plugin failed=0
  for spec in "${CLAUDE_PLUGINS[@]}"; do
    repo="${spec%% *}"
    plugin="${spec#* }"
    log "Marketplace ${repo} -> installing ${plugin}..."
    # Re-adding an existing marketplace is a no-op/refresh; real problems
    # (repo unreachable, bad manifest) surface at the install step below.
    "$claude" plugin marketplace add "$repo" >/dev/null 2>&1 || true
    if "$claude" plugin install "$plugin" >/dev/null 2>&1 \
       || "$claude" plugin list 2>/dev/null | grep -q "${plugin%%@*}"; then
      ok "  ${plugin}"
    else
      err "  ${plugin} failed (try: claude plugin marketplace add ${repo} && claude plugin install ${plugin})"
      failed=1
    fi
  done

  if [[ $failed -ne 0 ]]; then
    return 1
  fi
  ok "All plugins installed. Inspect with 'claude plugin list' (or /plugin in a session)."
}

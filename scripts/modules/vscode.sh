# shellcheck shell=bash
# Module: Visual Studio Code — Microsoft's official apt repository, stable
# channel — plus a curated extension set. The 'code' package auto-updates
# through apt; 'code --install-extension' resolves the newest extension
# version compatible with the installed VS Code on its own, and --force
# keeps already-installed extensions at their latest on re-runs.
# https://code.visualstudio.com/docs/setup/linux

VSCODE_EXTENSIONS=(
  anthropic.claude-code                          # Claude Code
  openai.chatgpt                                 # Codex (OpenAI)
  ms-python.python                               # Python (Microsoft)
  ms-vscode.cpptools-extension-pack              # C/C++ Extension Pack
  vscjava.vscode-java-pack                       # Extension Pack for Java
  rust-lang.rust-analyzer                        # rust-analyzer
  redhat.ansible                                 # Ansible (Red Hat)
  redhat.vscode-yaml                             # YAML (Red Hat)
  golang.go                                      # Go (go.dev)
  vadimcn.vscode-lldb                            # CodeLLDB
  ms-vscode-remote.vscode-remote-extensionpack   # Remote Development
  ms-kubernetes-tools.vscode-kubernetes-tools    # Kubernetes (Microsoft)
  ms-azuretools.vscode-docker                    # Docker (Microsoft)
)

module_vscode_describe() { echo "Visual Studio Code (Microsoft apt repo, stable; curated extension set)"; }

module_vscode_install() {
  section "Visual Studio Code"

  add_apt_repo vscode \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main"
  apt_install code

  ok "Installed: $(code --version 2>/dev/null | head -n1 || echo 'code (version check needs a non-root shell)')"

  if confirm "Install the curated extension set (Claude Code, Codex, Python, C/C++, Java, rust-analyzer, Ansible, YAML, Go, CodeLLDB, Remote Dev, Kubernetes, Docker)?" y; then
    local ext failed=0
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
      if code --install-extension "$ext" --force >/dev/null 2>&1; then
        ok "  $ext"
      else
        err "  $ext failed (try: code --install-extension $ext)"
        failed=1
      fi
    done
    if [[ $failed -ne 0 ]]; then
      return 1
    fi
  fi

  log "Launch with 'code'; extensions live per-user under ~/.vscode."
}

# shellcheck shell=bash
# Module: Visual Studio Code — Microsoft's official repositories on every
# target OS (apt repo on the Debian family, yum repo on Enterprise Linux),
# stable channel — plus a curated extension set. The 'code' package
# auto-updates through the repo; 'code --install-extension' resolves the
# newest extension version compatible with the installed VS Code on its
# own, and --force keeps already-installed extensions at their latest.
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
  ms-vscode.remote-explorer                      # Remote Explorer (Microsoft)
  ms-vscode-remote.remote-ssh-edit               # Remote - SSH: Editing Configuration Files
  ms-kubernetes-tools.vscode-kubernetes-tools    # Kubernetes (Microsoft)
  ms-azuretools.vscode-docker                    # Docker (Microsoft)
  amazonwebservices.aws-toolkit-vscode           # AWS Toolkit (AWS)
  github.remotehub                               # GitHub Repositories (GitHub)
  gitlab.gitlab-workflow                         # GitLab Workflow (GitLab)
  codezombiech.gitignore                         # gitignore (CodeZombie)
  eamodio.gitlens                                # GitLens (GitKraken)
)

module_vscode_describe() { echo "Visual Studio Code (Microsoft repo, stable; curated extension set)"; }

module_vscode_install() {
  section "Visual Studio Code"

  if [[ "$(os_family)" == deb ]]; then
    add_apt_repo vscode \
      "https://packages.microsoft.com/keys/microsoft.asc" \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main"
    apt_install code
  else
    # Microsoft's official yum repo, per the VS Code Linux setup docs.
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    sudo dnf install -y code
  fi

  ok "Installed: $(code --version 2>/dev/null | head -n1 || echo 'code (version check needs a non-root shell)')"

  if confirm "Install the curated extension set (Claude Code, Codex, Python, C/C++, Java, rust-analyzer, Ansible, YAML, Go, CodeLLDB, Remote Dev/Explorer/SSH-edit, Kubernetes, Docker, AWS Toolkit, GitHub Repos, GitLab, gitignore, GitLens)?" y; then
    local ext failed=0 installed
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
      # Marketplace downloads can be cut mid-transfer on flaky networks —
      # retry before calling it a failure, the same philosophy as fetch's
      # --retry on every other download in this repo.
      installed=""
      for _ in 1 2 3; do
        if code --install-extension "$ext" --force >/dev/null 2>&1; then
          installed=1
          break
        fi
        sleep 2
      done
      if [[ -n "$installed" ]]; then
        ok "  $ext"
      else
        err "  $ext failed 3 times (try: code --install-extension $ext)"
        failed=1
      fi
    done
    if [[ $failed -ne 0 ]]; then
      return 1
    fi
  fi

  log "Launch with 'code'; extensions live per-user under ~/.vscode."
}

# shellcheck shell=bash
# Module: Go — official binary release into /usr/local/go.
# GO_VERSION=latest resolves the current stable via go.dev; pin in
# config/versions.env for strict repeatability.

module_golang_describe() { echo "Go (official go.dev binary, ${GO_VERSION})"; }

module_golang_install() {
  section "Go"
  local version="$GO_VERSION"
  if [[ "$version" == "latest" ]]; then
    version="$(fetch 'https://go.dev/VERSION?m=text' | head -n1)"   # e.g. go1.25.0
    [[ "$version" == go* ]] || die "Could not resolve latest Go version from go.dev."
  fi

  local tarball="${version}.linux-amd64.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  fetch "https://go.dev/dl/${tarball}" -o "${tmp}/${tarball}"

  # Per official docs: remove any previous /usr/local/go before extracting.
  sudo rm -rf /usr/local/go
  sudo tar -xzf "${tmp}/${tarball}" -C /usr/local
  rm -rf "$tmp"

  sudo tee /etc/profile.d/golang.sh >/dev/null <<'EOF'
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
EOF
  sudo chmod +x /etc/profile.d/golang.sh

  ok "Installed: $(/usr/local/go/bin/go version)"
  log "Open a new shell (or 'source /etc/profile.d/golang.sh') to get 'go' on PATH."
}

module_golang_uninstall() {
  section "Uninstall: Go"
  sudo rm -rf /usr/local/go /etc/profile.d/golang.sh
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/go"
    log "Purged ~/go (GOPATH: modules cache, installed binaries)."
  else
    log "Kept: ~/go (--purge-data removes it)."
  fi
}

# shellcheck shell=bash
# Module: Podman — daemonless containers running ROOTLESS (as your user):
# the Docker alternative that is native on Enterprise Linux and packaged in
# every Debian-family archive. Coexists with Docker Engine; only the
# podman-docker CLI shim would conflict, and this module does not install it.

module_podman_describe() { echo "Podman (rootless containers as your user — Docker alternative)"; }

module_podman_install() {
  section "Podman (rootless)"
  if command_exists apt-get; then
    # uidmap provides newuidmap/newgidmap for rootless; the network backend
    # (pasta/slirp4netns) arrives via podman's Recommends.
    apt_install podman uidmap
  else
    sudo dnf install -y podman
  fi

  # Rootless operation needs subordinate UID/GID ranges for the user.
  if ! grep -q "^${USER}:" /etc/subuid 2>/dev/null \
      || ! grep -q "^${USER}:" /etc/subgid 2>/dev/null; then
    log "Adding subordinate UID/GID ranges for ${USER} (rootless containers need them)."
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
    # Make podman pick the fresh ranges up without a re-login.
    podman system migrate >/dev/null 2>&1 || true
  fi

  ok "Installed: $(podman --version)"
  if [[ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" == "true" ]]; then
    ok "Rootless mode verified: podman runs as ${USER}, no daemon, no root."
  else
    warn "Could not verify rootless operation in this environment — on a real"
    warn "machine, 'podman info' run as ${USER} should report rootless: true."
  fi
  log "Docker-CLI compat: the 'podman-docker' package aliases 'docker' to podman —"
  log "skip it if Docker Engine is also installed (the two shims conflict)."
  log "Compose: 'podman compose' delegates to podman-compose or docker-compose."
}

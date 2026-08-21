# shellcheck shell=bash
# Module: Docker Engine — Docker's official repositories, per target OS:
# apt repos for Ubuntu and Debian (deb822), dnf repos for Rocky (Docker's
# centos repo, per Docker's docs) and RHEL. PureOS has no Docker suite —
# the podman module covers containers there. NVIDIA Container Toolkit is
# added on apt-family systems when an NVIDIA driver is present.
# https://docs.docker.com/engine/install/

module_docker_describe() { echo "Docker Engine + Compose plugin (official Docker repo)"; }

module_docker_install() {
  section "Docker Engine"
  local os="${TARGET_OS:-ubuntu}"
  local pkg suite fallback repo
  case "$os" in
    ubuntu|debian)
      # Remove distro/snap variants that conflict with docker-ce.
      for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
      done

      # shellcheck disable=SC1091
      . /etc/os-release
      if [[ "$os" == "ubuntu" ]]; then
        suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
        fallback="noble"
      else
        suite="${VERSION_CODENAME:-}"
        fallback="trixie"
      fi
      # Docker officially supports current releases, but guard against repo
      # metadata lagging a brand-new codename — fall back to the prior one.
      if ! fetch --head "https://download.docker.com/linux/${os}/dists/${suite}/Release" >/dev/null 2>&1; then
        warn "Docker repo has no '${suite}' suite yet; using '${fallback}' as documented fallback."
        suite="$fallback"
      fi
      # deb822 .sources format, per Docker's current install docs.
      sudo install -m 0755 -d /etc/apt/keyrings
      fetch "https://download.docker.com/linux/${os}/gpg" | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
      sudo chmod a+r /etc/apt/keyrings/docker.asc
      sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${os}
Suites: ${suite}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
      _APT_UPDATED=""

      apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    rocky|rhel)
      # Rocky uses Docker's centos repo, RHEL its rhel repo (Docker's docs).
      repo="centos"
      [[ "$os" == "rhel" ]] && repo="rhel"
      # Remove only legacy docker packages — NOT podman: modern docker-ce
      # coexists with it, and podman may be a selected module here too.
      sudo dnf remove -y docker docker-client docker-common docker-engine >/dev/null 2>&1 || true
      sudo dnf install -y dnf-plugins-core
      # dnf4 and dnf5 spell repo-adding differently; try both.
      sudo dnf config-manager --add-repo "https://download.docker.com/linux/${repo}/docker-ce.repo" 2>/dev/null \
        || sudo dnf config-manager addrepo --from-repofile="https://download.docker.com/linux/${repo}/docker-ce.repo"
      sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      err "Docker Engine has no official repo path for '${os}' — use the podman module there."
      return 1
      ;;
  esac

  sudo systemctl enable --now docker

  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    warn "Added $USER to the 'docker' group. Log out/in (or run 'newgrp docker') before using docker without sudo."
  fi

  ok "Installed: $(docker --version) / $(docker compose version | head -n1)"

  # GPU containers: install the NVIDIA Container Toolkit if the driver is present.
  if command_exists nvidia-smi; then
    if ! command_exists apt-get; then
      log "NVIDIA driver detected: on Enterprise Linux add the NVIDIA Container"
      log "Toolkit from NVIDIA's dnf repo (not automated here — see their docs)."
    elif confirm "NVIDIA driver detected — install NVIDIA Container Toolkit for GPU containers?" y; then
      add_apt_repo nvidia-container-toolkit \
        "https://nvidia.github.io/libnvidia-container/gpgkey" \
        "deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /"
      apt_install nvidia-container-toolkit
      sudo nvidia-ctk runtime configure --runtime=docker
      sudo systemctl restart docker
      ok "NVIDIA Container Toolkit configured (test: docker run --rm --gpus all ubuntu nvidia-smi)."
    fi
  else
    log "No NVIDIA driver detected; skipping NVIDIA Container Toolkit (re-run this module after installing the driver — see github.com/asanderson/dual-boot)."
  fi
}

module_docker_uninstall() {
  section "Uninstall: Docker Engine"
  sudo systemctl disable --now docker 2>/dev/null || true
  pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit
  sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc \
    /etc/apt/sources.list.d/nvidia-container-toolkit.list /etc/apt/keyrings/nvidia-container-toolkit.gpg \
    /etc/yum.repos.d/docker-ce.repo
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    sudo rm -rf /var/lib/docker /var/lib/containerd
    log "Purged /var/lib/docker and /var/lib/containerd (images, volumes, containers)."
  else
    log "Kept: /var/lib/docker (images/volumes — --purge-data removes it)."
  fi
}

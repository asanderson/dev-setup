# shellcheck shell=bash
# Module: Docker Engine — official Docker apt repository (docker-ce), plus
# the NVIDIA Container Toolkit when an NVIDIA driver is present.
# https://docs.docker.com/engine/install/ubuntu/

module_docker_describe() { echo "Docker Engine + Compose plugin (official Docker repo)"; }

module_docker_install() {
  section "Docker Engine"
  # Remove distro/snap variants that conflict with docker-ce.
  local pkg
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y "$pkg" >/dev/null 2>&1 || true
  done

  # shellcheck disable=SC1091
  . /etc/os-release
  local suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  # Docker officially supports Ubuntu 26.04 ("resolute"), but guard against
  # repo metadata lagging a brand-new codename — fall back to the prior LTS.
  if ! fetch --head "https://download.docker.com/linux/ubuntu/dists/${suite}/Release" >/dev/null 2>&1; then
    warn "Docker repo has no '${suite}' suite yet; using 'noble' as documented fallback."
    suite="noble"
  fi
  # deb822 .sources format, per Docker's current install docs.
  sudo install -m 0755 -d /etc/apt/keyrings
  fetch https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${suite}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  _APT_UPDATED=""

  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo systemctl enable --now docker

  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    warn "Added $USER to the 'docker' group. Log out/in (or run 'newgrp docker') before using docker without sudo."
  fi

  ok "Installed: $(docker --version) / $(docker compose version | head -n1)"

  # GPU containers: install the NVIDIA Container Toolkit if the driver is present.
  if command_exists nvidia-smi; then
    if confirm "NVIDIA driver detected — install NVIDIA Container Toolkit for GPU containers?" y; then
      add_apt_repo nvidia-container-toolkit \
        "https://nvidia.github.io/libnvidia-container/gpgkey" \
        "deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /"
      apt_install nvidia-container-toolkit
      sudo nvidia-ctk runtime configure --runtime=docker
      sudo systemctl restart docker
      ok "NVIDIA Container Toolkit configured (test: docker run --rm --gpus all ubuntu nvidia-smi)."
    fi
  else
    log "No NVIDIA driver detected; skipping NVIDIA Container Toolkit (re-run after scripts/10-nvidia-driver.sh)."
  fi
}

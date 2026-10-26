# shellcheck shell=bash
# Module: CUDA Toolkit — NVIDIA's compiler (nvcc), runtime libraries and
# tools, from NVIDIA's CUDA network repository (latest release via the
# cuda-toolkit meta-package; the driver is the nvidia-driver module's
# job). Ubuntu, Debian and Enterprise Linux each have a repo; NVIDIA
# publishes none for PureOS. Installs under /usr/local/cuda, put on PATH
# by /etc/profile.d/cuda.sh. Works without a GPU (build hosts, images).
# https://docs.nvidia.com/cuda/cuda-installation-guide-linux/

module_cuda_toolkit_describe() { echo "CUDA Toolkit (NVIDIA CUDA repo, latest — nvcc + libraries)"; }

module_cuda_toolkit_install() {
  section "CUDA Toolkit"
  add_cuda_repo
  if [[ "$(os_family)" == deb ]]; then
    apt_install cuda-toolkit
  else
    sudo dnf install -y cuda-toolkit
  fi
  # shellcheck disable=SC2016
  printf '%s\n' '# CUDA Toolkit (dev-setup cuda-toolkit module)' \
    'case ":$PATH:" in *:/usr/local/cuda/bin:*) ;; *) export PATH="/usr/local/cuda/bin:$PATH" ;; esac' \
    | sudo tee /etc/profile.d/cuda.sh >/dev/null
  # Runtime libraries (libcudart, cuBLAS) for CUDA-built binaries such as
  # the llama-cpp module's, through the version-independent symlink.
  echo /usr/local/cuda/lib64 | sudo tee /etc/ld.so.conf.d/dev-setup-cuda.conf >/dev/null
  sudo ldconfig
  export PATH="/usr/local/cuda/bin:$PATH"
  ok "Installed: $(nvcc --version | grep -m1 release)"
  if ! has_nvidia_gpu; then
    log "No NVIDIA GPU here — the toolkit builds CUDA code; running it needs a GPU + the nvidia-driver module."
  fi
}

module_cuda_toolkit_uninstall() {
  section "Uninstall: CUDA Toolkit"
  local -a pkgs
  if command_exists dpkg; then
    mapfile -t pkgs < <(dpkg-query -W -f='${Package}\n' 'cuda-*' 'libcublas*' 'libcufft*' 'libcurand*' \
      'libcusolver*' 'libcusparse*' 'libnpp*' 'libnvjitlink*' 'libnvjpeg*' 'nsight-*' 2>/dev/null \
      | grep -v '^cuda-keyring$' || true)
  else
    mapfile -t pkgs < <(rpm -qa --qf '%{NAME}\n' 'cuda-*' 'libcublas*' 'libcufft*' 'libcurand*' \
      'libcusolver*' 'libcusparse*' 'libnpp*' 'libnvjitlink*' 'libnvjpeg*' 'nsight-*' 2>/dev/null || true)
  fi
  pkg_remove "${pkgs[@]}"
  sudo rm -f /etc/profile.d/cuda.sh /etc/ld.so.conf.d/dev-setup-cuda.conf
  sudo ldconfig
  # The repo stays when the nvidia-driver module's packages still use it.
  if ! { dpkg -s nvidia-open >/dev/null 2>&1 || rpm -q nvidia-open >/dev/null 2>&1; }; then
    pkg_remove cuda-keyring
    sudo rm -f /etc/yum.repos.d/cuda-rhel*.repo
  fi
  log "Removed the CUDA Toolkit packages (the NVIDIA driver, if installed, is untouched)."
}

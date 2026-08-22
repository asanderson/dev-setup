# shellcheck shell=bash
# Module: C/C++ toolchain — GCC (default), Clang/LLVM, and the usual build
# tooling on every target OS: distro packages everywhere, plus the newest
# Clang/LLVM release from apt.llvm.org where a suite exists for the target
# (Ubuntu and Debian; PureOS codenames and Enterprise Linux have no
# apt.llvm.org channel — their archive clang is what there is).

module_cpp_describe() { echo "C/C++ toolchain (GCC, Clang, CMake, Ninja, gdb, valgrind; newest LLVM ${LLVM_VERSION} where available)"; }

module_cpp_install() {
  section "C/C++ toolchain"
  if [[ "$(os_family)" == deb ]]; then
    apt_install \
      build-essential gcc g++ gdb \
      clang clangd clang-format clang-tidy lldb llvm \
      cmake ninja-build ccache \
      valgrind \
      pkg-config autoconf automake libtool \
      manpages-dev
  else
    # ccache and ninja-build live in EPEL/CRB on Enterprise Linux: enable
    # both best-effort (unentitled UBI containers can't reach CRB), then
    # treat those two as optional extras so the core toolchain always lands.
    sudo dnf install -y epel-release 2>/dev/null \
      || sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm" 2>/dev/null \
      || true
    sudo dnf config-manager --set-enabled crb 2>/dev/null \
      || sudo dnf config-manager setopt crb.enabled=1 2>/dev/null \
      || true
    sudo dnf install -y \
      gcc gcc-c++ gdb make \
      clang clang-tools-extra lldb lld llvm \
      cmake \
      valgrind \
      pkgconf autoconf automake libtool
    sudo dnf install -y ninja-build ccache \
      || warn "ninja-build/ccache unavailable in this EL repo set (EPEL/CRB needed) — skipped."
  fi

  ok "GCC:   $(gcc --version | head -n1)"
  ok "Clang: $(clang --version | head -n1)"
  ok "CMake: $(cmake --version | head -n1)"

  # Newest Clang/LLVM release from the official apt.llvm.org repo — Ubuntu
  # and Debian suites exist; the versioned packages (clang-N, clangd-N, ...)
  # install alongside the archive toolchain ('clang' stays the archive
  # default). Bump LLVM_VERSION in config/versions.env as majors go final.
  case "${TARGET_OS:-ubuntu}" in
    ubuntu|debian)
      if confirm "Also install the newest Clang/LLVM (${LLVM_VERSION}) from apt.llvm.org?" y; then
        # shellcheck disable=SC1091
        . /etc/os-release
        local suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
        add_apt_repo llvm \
          "https://apt.llvm.org/llvm-snapshot.gpg.key" \
          "deb [signed-by=/etc/apt/keyrings/llvm.gpg] https://apt.llvm.org/${suite}/ llvm-toolchain-${suite}-${LLVM_VERSION} main"
        apt_install \
          "clang-${LLVM_VERSION}" "clangd-${LLVM_VERSION}" \
          "clang-format-${LLVM_VERSION}" "clang-tidy-${LLVM_VERSION}" \
          "lld-${LLVM_VERSION}" "lldb-${LLVM_VERSION}" "llvm-${LLVM_VERSION}"
        ok "LLVM ${LLVM_VERSION}: $("clang-${LLVM_VERSION}" --version | head -n1) (as clang-${LLVM_VERSION}, clangd-${LLVM_VERSION}, ...)"
      fi
      ;;
    *)
      log "apt.llvm.org has no ${TARGET_OS} channel — the archive Clang above is the newest packaged one here."
      ;;
  esac
}

module_cpp_uninstall() {
  section "Uninstall: C/C++ toolchain"
  pkg_remove \
    build-essential gdb clang clangd clang-format clang-tidy lldb llvm \
    cmake ninja-build ccache valgrind \
    "clang-${LLVM_VERSION}" "clangd-${LLVM_VERSION}" "clang-format-${LLVM_VERSION}" \
    "clang-tidy-${LLVM_VERSION}" "lld-${LLVM_VERSION}" "lldb-${LLVM_VERSION}" "llvm-${LLVM_VERSION}" \
    gcc-c++ clang-tools-extra lld
  sudo rm -f /etc/apt/sources.list.d/llvm.list /etc/apt/keyrings/llvm.gpg
  log "Kept: gcc/libc on the Debian family where other packages depend on them (apt removes only what is safe)."
}

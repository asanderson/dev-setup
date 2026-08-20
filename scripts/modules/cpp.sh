# shellcheck shell=bash
# Module: C/C++ toolchain — GCC (default), Clang/LLVM, and the usual build
# tooling from the Ubuntu archive, plus the newest Clang/LLVM release from
# apt.llvm.org (versioned packages, side by side with the archive clang).

module_cpp_describe() { echo "C/C++ toolchain (GCC, Clang, CMake, Ninja, gdb, valgrind; newest LLVM ${LLVM_VERSION})"; }

module_cpp_install() {
  section "C/C++ toolchain"
  apt_install \
    build-essential gcc g++ gdb \
    clang clangd clang-format clang-tidy lldb llvm \
    cmake ninja-build ccache \
    valgrind \
    pkg-config autoconf automake libtool \
    manpages-dev

  ok "GCC:   $(gcc --version | head -n1)"
  ok "Clang: $(clang --version | head -n1)"
  ok "CMake: $(cmake --version | head -n1)"

  # Newest Clang/LLVM release from the official apt.llvm.org repo. The
  # versioned packages (clang-N, clangd-N, ...) install alongside the archive
  # toolchain above — 'clang' stays the archive default, 'clang-N' is the new
  # release. Bump LLVM_VERSION in config/versions.env as majors go final.
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
}

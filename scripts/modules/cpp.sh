# shellcheck shell=bash
# Module: C/C++ toolchain — GCC (default), Clang/LLVM, and the usual build tooling.

module_cpp_describe() { echo "C/C++ toolchain (GCC, Clang, CMake, Ninja, gdb, valgrind)"; }

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
}

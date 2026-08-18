# shellcheck shell=bash
# Module: Rust — official rustup installer (stable toolchain).
# https://rustup.rs

module_rust_describe() { echo "Rust (rustup, stable toolchain + clippy + rustfmt)"; }

module_rust_install() {
  section "Rust"
  if command_exists rustup; then
    log "rustup already present; updating toolchain instead of reinstalling."
    rustup update stable
  else
    fetch https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi

  "$HOME/.cargo/bin/rustup" component add clippy rustfmt >/dev/null 2>&1 || true

  ok "Installed: $("$HOME/.cargo/bin/rustc" --version)"
  log "cargo/rustc live in ~/.cargo/bin (added to PATH via ~/.cargo/env in your shell rc)."
}

# shellcheck shell=bash
# Module: 7-Zip — Igor Pavlov's official Linux build at the SEVENZIP_VERSION
# pin, from the project's own GitHub releases (ip7z/7zip), SHA-256
# verified against SEVENZIP_SHA256. The statically linked 7zzs build is
# installed as /usr/local/bin/7zz, so it is identical on every target OS
# (PureOS byzantium still ships only the abandoned p7zip fork, and the
# distro builds lag), plus a 7z alias when nothing else provides one.
# https://www.7-zip.org/download.html

module_7zip_describe() { echo "7-Zip ${SEVENZIP_VERSION} (official 7zz build)"; }

module_7zip_install() {
  section "7-Zip"
  local want="${SEVENZIP_VERSION}" have tmp
  have="$(/usr/local/bin/7zz 2>/dev/null | grep -o '7-Zip (z) [0-9.]*' | awk '{print $3}' || true)"
  if [[ "$have" == "$want" ]]; then
    ok "7-Zip ${want} already installed."
  else
    if [[ "$(os_family)" == deb ]]; then apt_install xz-utils; else sudo dnf install -y xz tar; fi
    tmp="$(mktemp -d)"
    fetch "https://github.com/ip7z/7zip/releases/download/${want}/7z${want//./}-linux-x64.tar.xz" -o "${tmp}/7z.tar.xz"
    echo "${SEVENZIP_SHA256}  ${tmp}/7z.tar.xz" | sha256sum -c --quiet - \
      || { rm -rf "$tmp"; err "7-Zip ${want} tarball failed its SHA-256 check."; return 1; }
    tar -xJf "${tmp}/7z.tar.xz" -C "$tmp"
    sudo install -m 0755 "$(find "$tmp" -type f -name 7zzs | head -n1)" /usr/local/bin/7zz
    rm -rf "$tmp"
  fi
  if ! command_exists 7z || [[ "$(readlink /usr/local/bin/7z 2>/dev/null)" == 7zz ]]; then
    sudo ln -sf 7zz /usr/local/bin/7z
  fi
  ok "Installed: $(/usr/local/bin/7zz | grep -m1 '7-Zip')"
}

module_7zip_uninstall() {
  section "Uninstall: 7-Zip"
  [[ "$(readlink /usr/local/bin/7z 2>/dev/null)" == 7zz ]] && sudo rm -f /usr/local/bin/7z
  sudo rm -f /usr/local/bin/7zz
  log "Removed /usr/local/bin/7zz (distro p7zip/7zip packages, if any, are left alone)."
}

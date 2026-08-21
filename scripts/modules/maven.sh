# shellcheck shell=bash
# Module: Apache Maven — pinned upstream binary into /opt (Ubuntu's `maven`
# package lags upstream). Version pinned in config/versions.env.

module_maven_describe() { echo "Apache Maven ${MAVEN_VERSION} (/opt/apache-maven, pinned)"; }

module_maven_install() {
  section "Apache Maven ${MAVEN_VERSION}"
  if ! command_exists java; then
    warn "No JDK detected. Maven needs a JDK — select the JDK module too."
  fi

  local base="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries"
  local tarball="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  local dest="/opt/apache-maven-${MAVEN_VERSION}"
  local tmp; tmp="$(mktemp -d)"

  # dlcdn hosts only the newest release; superseded versions live in the archive.
  if ! fetch --head "${base}/${tarball}" >/dev/null 2>&1; then
    warn "Maven ${MAVEN_VERSION} not on dlcdn (superseded?); using archive.apache.org."
    base="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries"
  fi

  fetch "${base}/${tarball}" -o "${tmp}/${tarball}"
  fetch "${base}/${tarball}.sha512" -o "${tmp}/${tarball}.sha512"
  ( cd "$tmp" && echo "$(cat "${tarball}.sha512")  ${tarball}" | sha512sum -c - ) \
    || die "Maven tarball checksum mismatch — aborting."

  sudo rm -rf "$dest"
  sudo tar -xzf "${tmp}/${tarball}" -C /opt
  sudo ln -sfn "$dest" /opt/maven
  rm -rf "$tmp"

  sudo tee /etc/profile.d/maven.sh >/dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH="$M2_HOME/bin:$PATH"
EOF
  sudo chmod +x /etc/profile.d/maven.sh

  ok "Installed: $(/opt/maven/bin/mvn -version 2>/dev/null | head -n1)"
  log "Open a new shell (or 'source /etc/profile.d/maven.sh') to get 'mvn' on PATH."
}

module_maven_uninstall() {
  section "Uninstall: Maven"
  sudo rm -rf /opt/apache-maven-* /opt/maven /etc/profile.d/maven.sh
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.m2"
    log "Purged ~/.m2 (local repository)."
  else
    log "Kept: ~/.m2 (--purge-data removes it)."
  fi
}

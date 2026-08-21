# shellcheck shell=bash
# Module: JDK — latest LTS Java on every target OS: the distro's OpenJDK
# packages (apt or dnf), or Eclipse Temurin from the Adoptium apt
# repository on the Debian family.

module_jdk_describe() { echo "JDK ${JDK_MAJOR} LTS (OpenJDK or Eclipse Temurin)"; }

module_jdk_install() {
  section "JDK ${JDK_MAJOR} (LTS)"

  if [[ "$(os_family)" == rpm ]]; then
    # Red Hat ships new OpenJDK majors in the AppStream repos; fall back to
    # the newest packaged one when the pinned major hasn't landed yet.
    if ! sudo dnf install -y "java-${JDK_MAJOR}-openjdk-devel"; then
      warn "java-${JDK_MAJOR}-openjdk-devel not packaged here yet; installing the newest available OpenJDK."
      sudo dnf install -y java-latest-openjdk-devel \
        || sudo dnf install -y java-21-openjdk-devel
    fi
    ok "Installed: $(java -version 2>&1 | head -n1)"
    log "JAVA_HOME resolves via alternatives; explicit export usually unnecessary."
    return 0
  fi

  local choice
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    choice=1
    log "DEV_SETUP_ASSUME_YES=1 — defaulting to the distro OpenJDK packages."
  else
    echo "  1) Distro OpenJDK packages (openjdk-${JDK_MAJOR}-jdk) — simplest, distro-patched"
    echo "  2) Eclipse Temurin ${JDK_MAJOR} (Adoptium apt repo) — upstream builds, fastest updates"
    read -r -p "${C_BOLD}Which JDK?${C_RESET} [1/2, default 1] " choice
  fi

  if [[ "$choice" == "2" ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    local suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    # The Adoptium repo may not have published metadata for a brand-new Ubuntu
    # release yet (e.g. 26.04 "resolute"); its .deb packages are
    # release-agnostic, so fall back to the previous LTS suite.
    if ! fetch --head "https://packages.adoptium.net/artifactory/deb/dists/${suite}/Release" >/dev/null 2>&1; then
      warn "Adoptium has no '${suite}' suite yet; using 'noble' (packages are identical)."
      suite="noble"
    fi
    add_apt_repo adoptium \
      "https://packages.adoptium.net/artifactory/api/gpg/key/public" \
      "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${suite} main"
    apt_install "temurin-${JDK_MAJOR}-jdk"
  else
    if ! apt_install "openjdk-${JDK_MAJOR}-jdk"; then
      warn "openjdk-${JDK_MAJOR}-jdk not in the archive yet; falling back to default-jdk."
      apt_install default-jdk
    fi
  fi

  ok "Installed: $(java -version 2>&1 | head -n1)"
  log "JAVA_HOME resolves via update-alternatives; explicit export usually unnecessary."
}

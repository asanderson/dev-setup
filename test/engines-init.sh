#!/usr/bin/env bash
# engines-init.sh — runs INSIDE a fresh container of a TARGET OS (as root).
# Bootstraps per package family (apt or dnf), creates a non-root user with
# passwordless sudo, runs the installer unattended scoped to the
# container-engine modules for that OS, and verifies the results.
#
# Invoked by test/engines-test.sh — not meant to be run on a real machine.
#
# Usage: engines-init.sh <target-os> "<space-separated module list>"
# Mounts expected: /repo (this repository, read-only).
# Optional proxy support mirrors container-init.sh: with $https_proxy set,
# package sources switch to HTTPS through it, and a CA at /ccr-ca.crt is
# trusted (CONNECT-only MITM proxies, e.g. sandboxed CI environments).
set -euo pipefail

TARGET="${1:?target os required}"
MODULES_OVERRIDE="${2:?module list required}"

unset http_proxy HTTP_PROXY   # CONNECT-only proxies reject plain-HTTP proxying

FAMILY=rpm
command -v apt-get >/dev/null 2>&1 && FAMILY=deb
echo "### [init] ${TARGET} (${FAMILY} family) bootstrap$( [[ -n "${https_proxy:-}" ]] && echo ' (via proxy)' )"

if [[ "$FAMILY" == deb ]]; then
  if [[ -n "${https_proxy:-}" ]]; then
    # Sources layout differs per image (classic list vs deb822) — force
    # https on whichever exists so the CONNECT-only proxy can carry apt.
    sed -i 's|http://|https://|g' /etc/apt/sources.list 2>/dev/null || true
    sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || true
    sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.list 2>/dev/null || true
    {
      echo "Acquire::https::Proxy \"${https_proxy}\";"
      [[ -f /ccr-ca.crt ]] && echo 'Acquire::https::CAInfo "/ccr-ca.crt";'
    } >/etc/apt/apt.conf.d/95proxy
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates sudo curl gnupg openssl >/dev/null
  if [[ -f /ccr-ca.crt ]]; then
    cp /ccr-ca.crt /usr/local/share/ca-certificates/agent-proxy.crt
    update-ca-certificates >/dev/null
  fi
else
  if [[ -n "${https_proxy:-}" ]]; then
    echo "proxy=${https_proxy}" >>/etc/dnf/dnf.conf
    # A CONNECT-only proxy rejects plain-HTTP proxying, and EL mirrorlists
    # hand out http package URLs — pin the repos to their https baseurls.
    sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=http://|baseurl=https://|' \
      /etc/yum.repos.d/*.repo 2>/dev/null || true
    if [[ -f /ccr-ca.crt ]]; then
      cp /ccr-ca.crt /etc/pki/ca-trust/source/anchors/agent-proxy.crt
      update-ca-trust
    fi
  fi
  dnf install -y sudo shadow-utils ca-certificates >/dev/null
fi

if [[ ! -d /run/systemd/system ]]; then
  # No running systemd in a container, and the modules' service steps must
  # not decide the test: EL base images lack systemctl entirely, and
  # Debian 13's systemd refuses `enable --now` outright where Ubuntu's
  # no-ops. A no-op stub in /usr/local/bin stays ahead of any real
  # systemctl that a module's dependency chain installs later; the
  # sudoers secure_path below makes sudo see it on EL too.
  cat >/usr/local/bin/systemctl <<'EOF'
#!/bin/sh
echo "systemctl stub (container test): ignoring: $*"
exit 0
EOF
  chmod +x /usr/local/bin/systemctl
  echo "### [init] installed a no-op systemctl stub (no running systemd here)"
fi

echo "### [init] create test user 'dev' with passwordless sudo"
useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev
echo 'Defaults env_keep += "https_proxy no_proxy HTTPS_PROXY NO_PROXY DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env
# /usr/local/bin first so the systemctl stub wins under sudo (EL's default
# secure_path omits it; this matches the Debian-family default).
echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >/etc/sudoers.d/secure-path
chmod 440 /etc/sudoers.d/dev /etc/sudoers.d/proxy-env /etc/sudoers.d/secure-path

echo "### [init] copy repo; will run: setup.sh --os ${TARGET} --modules ${MODULES_OVERRIDE// /,}"
cp -r /repo /home/dev/dev-setup
chown -R dev:dev /home/dev/dev-setup

if [[ "$TARGET" == "pureos" ]]; then
  echo "### [flags] docker must be refused on pureos (podman covers it there)"
  out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
    bash -c 'cd ~/dev-setup && ./scripts/setup.sh --os pureos --docker' 2>&1)" || true
  grep -q "docker: not supported on pureos" <<<"$out" \
    || { echo "FAIL: missing unsupported-component warning for docker on pureos"; exit 1; }
  grep -q "unattended runs never install unsupported" <<<"$out" \
    || { echo "FAIL: missing unattended skip notice"; exit 1; }
  echo "  PASS: docker warned + skipped on pureos"
fi

echo "### [run] setup.sh under DEV_SETUP_ASSUME_YES=1"
set +e
sudo -u dev -H env \
  https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
  DEV_SETUP_ASSUME_YES=1 \
  bash -c "cd ~/dev-setup && ./scripts/setup.sh --os ${TARGET} --modules ${MODULES_OVERRIDE// /,}"
rc=$?
set -e
echo "### [run] setup.sh exit code: ${rc}"

echo "### [verify] engine tools (login shell as dev)"
verify_rc=0
for m in ${MODULES_OVERRIDE}; do
  case "$m" in
    docker) probes=("docker --version" "docker compose version") ;;
    podman) probes=("podman --version") ;;
    *)      echo "  SKIP ${m} (not an engine module)"; continue ;;
  esac
  for probe in "${probes[@]}"; do
    # Capture fully, truncate after — a head-in-pipeline SIGPIPEs
    # multi-line probes under pipefail (see container-init.sh).
    if out=$(sudo -u dev -H bash -lc "$probe" 2>&1); then
      printf '  OK   %-8s %s\n' "$m" "${out%%$'\n'*}"
    else
      printf '  FAIL %-8s probe failed: %s\n' "$m" "$probe"
      verify_rc=1
    fi
  done
done
[[ $rc -eq 0 && $verify_rc -ne 0 ]] && rc=$verify_rc

echo "### [done] ${TARGET} overall exit: ${rc}"
exit "${rc}"

#!/usr/bin/env bash
# gpu-path-init.sh — runs INSIDE a fresh Ubuntu container (as root; the
# container must be started with --privileged so a nested dockerd can run).
#
# Exercises the GPU-present branches that the default (GPU-less) test matrix
# can never reach, simulating the MSI Raider 18's RTX 5090 Laptop GPU with an
# nvidia-smi stub:
#   phase 1  docker module: GPU banner, NVIDIA Container Toolkit repo+package
#            install, nvidia-ctk writes the nvidia runtime into daemon.json
#   phase 2  dockerd starts and registers the nvidia runtime
#   phase 3  ollama module takes the GPU path (no CPU-fallback prompt)
# The stub validates branching and toolkit machinery, not CUDA execution —
# that still needs the real machine.
#
# Invoked by test/container-test.sh --gpu-path — not meant for a real machine.
# Mounts expected: /repo (this repository, read-only).
# Optional proxy support: if $https_proxy is set, apt sources switch to
# HTTPS and route through it; if /ccr-ca.crt is mounted, it is trusted
# (for CONNECT-only MITM proxies, e.g. sandboxed CI environments).
set -euo pipefail

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }

echo "### [init] apt bootstrap$( [[ -n "${https_proxy:-}" ]] && echo ' (via proxy)' )"
unset http_proxy HTTP_PROXY   # CONNECT-only proxies reject plain-HTTP proxying
if [[ -n "${https_proxy:-}" ]]; then
  sed -i 's|http://\(archive\|security\).ubuntu.com|https://\1.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources
  {
    echo "Acquire::https::Proxy \"${https_proxy}\";"
    [[ -f /ccr-ca.crt ]] && echo 'Acquire::https::CAInfo "/ccr-ca.crt";'
  } >/etc/apt/apt.conf.d/95proxy
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates sudo curl gnupg openssl procps >/dev/null
if [[ -f /ccr-ca.crt ]]; then
  cp /ccr-ca.crt /usr/local/share/ca-certificates/agent-proxy.crt
  update-ca-certificates >/dev/null
fi

echo "### [init] create test user 'dev' with passwordless sudo"
useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev
echo 'Defaults env_keep += "https_proxy no_proxy HTTPS_PROXY NO_PROXY DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env
chmod 440 /etc/sudoers.d/dev /etc/sudoers.d/proxy-env

echo "### [init] copy repo + nvidia-smi stub (RTX 5090 Laptop GPU / 595.91.07)"
cp -r /repo /home/dev/dev-setup
chown -R dev:dev /home/dev/dev-setup

cat >/usr/local/bin/nvidia-smi <<'STUB'
#!/bin/bash
# Test stub simulating the MSI Raider's GPU (no real GPU in this container).
case "$*" in
  *--query-gpu*) echo "NVIDIA GeForce RTX 5090 Laptop GPU, 595.91.07" ;;
  *) echo "NVIDIA-SMI 595.91.07 (stub) — GeForce RTX 5090 Laptop GPU" ;;
esac
exit 0
STUB
chmod +x /usr/local/bin/nvidia-smi

scope() { sed -i "s/^MODULES=(.*)$/MODULES=($1)/" /home/dev/dev-setup/scripts/setup.sh; }
run_setup() {
  sudo -u dev -H env \
    https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
    DEV_SETUP_ASSUME_YES=1 \
    bash -c 'cd ~/dev-setup && ./scripts/setup.sh'
}

echo "### [phase 1] docker module with GPU present (NVIDIA Container Toolkit branch)"
scope "docker"
set +e; p1="$(run_setup 2>&1)"; rc=$?; set -e
grep -q "GPU:.*RTX 5090" <<<"$p1" || fail "setup.sh did not print the GPU banner"
grep -q "NVIDIA driver not active" <<<"$p1" && fail "GPU-absent warning fired despite GPU present"
grep -q "skipping NVIDIA Container Toolkit" <<<"$p1" && fail "toolkit branch was skipped despite GPU present"
grep -q "NVIDIA driver detected — install NVIDIA Container Toolkit" <<<"$p1" || fail "toolkit prompt did not fire"
dpkg -s nvidia-container-toolkit >/dev/null 2>&1 || { echo "$p1" | tail -25; fail "nvidia-container-toolkit package not installed"; }
grep -q '"nvidia"' /etc/docker/daemon.json 2>/dev/null || fail "nvidia-ctk did not configure the nvidia runtime in daemon.json"
if [[ $rc -ne 0 ]]; then
  # The only acceptable failure here is (re)starting the docker service —
  # there is no systemd in the container; on a real host it succeeds.
  grep -Eq "systemctl|System has not been booted|Failed to.*docker" <<<"$p1" \
    || { echo "$p1" | tail -25; fail "docker module failed for a reason other than the systemd-less service (re)start"; }
  echo "  note: module exit ${rc} at the docker service (re)start — systemd-less container artifact"
fi
echo "  PASS: toolkit repo+package installed; daemon.json configured; GPU banner correct"

echo "### [phase 2] dockerd registers the nvidia runtime"
env HTTPS_PROXY="${https_proxy:-}" NO_PROXY="${no_proxy:-}" dockerd >/var/log/dockerd.log 2>&1 &
up=""
for _ in $(seq 1 20); do docker info >/dev/null 2>&1 && { up=1; break; }; sleep 3; done
if [[ -z "$up" ]]; then
  pkill dockerd 2>/dev/null || true; sleep 2
  env HTTPS_PROXY="${https_proxy:-}" NO_PROXY="${no_proxy:-}" dockerd --iptables=false >>/var/log/dockerd.log 2>&1 &
  for _ in $(seq 1 20); do docker info >/dev/null 2>&1 && { up=1; break; }; sleep 3; done
fi
[[ -n "$up" ]] || { tail -20 /var/log/dockerd.log; fail "dockerd did not start (with nvidia runtime configured)"; }
docker info --format '{{json .Runtimes}}' | grep -q nvidia || fail "dockerd did not register the nvidia runtime"
echo "  PASS: dockerd up with runtimes: $(docker info --format '{{json .Runtimes}}' | tr -d '"')"

echo "### [phase 3] ollama module takes the GPU path"
scope "ollama"
o1=""
for attempt in 1 2; do
  set +e; o1="$(run_setup 2>&1)"; orc=$?; set -e
  [[ $orc -eq 0 ]] && break
  # Retry once if the bundle download was cut mid-transfer; any other
  # failure — and a second cut — is a real failure.
  grep -qE "premature end|Unexpected EOF|connection dropped" <<<"$o1" \
    || { echo "$o1" | tail -20; fail "ollama failed for a non-download reason"; }
  [[ $attempt -eq 2 ]] && { echo "$o1" | tail -20; fail "ollama bundle download failed twice"; }
  echo "  note: attempt ${attempt} — bundle download was cut; retrying"
done
grep -q "fall back to CPU" <<<"$o1" && fail "CPU-fallback warning fired despite GPU present"
grep -q "Continue installing Ollama anyway" <<<"$o1" && fail "no-GPU confirm prompt fired despite GPU present"
echo "  PASS: ollama installed via the GPU path ($(ollama --version 2>/dev/null | head -1))"

echo "### [done] GPU-present paths verified"

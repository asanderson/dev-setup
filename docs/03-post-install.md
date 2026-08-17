# Step 3 — Post-install: NVIDIA driver, kernel check, dev tools

You're booted into Ubuntu 26.04 with this repo cloned at `~/dev-setup`.
Three scripts, in order:

```bash
cd ~/dev-setup
./scripts/10-nvidia-driver.sh   # NVIDIA driver (then REBOOT)
./scripts/20-kernel.sh          # confirm kernel 7.0+, optional newer kernels
./scripts/setup.sh              # interactive dev-tool installer
```

## 3.1 NVIDIA driver — `scripts/10-nvidia-driver.sh`

The RTX 5090 Laptop GPU (Blackwell) is supported **only by NVIDIA's open GPU
kernel modules** — the legacy proprietary kernel modules do not support this
generation. The production branch is **580** (pairs with CUDA 13.x); newer
branches such as **595** also carry Blackwell support. The script:

1. Checks Secure Boot state and explains **MOK enrollment** (below).
2. Runs `ubuntu-drivers devices` and installs the recommended driver,
   preferring the `-open` variant (e.g. `nvidia-driver-580-open`).
3. Optionally installs the CUDA toolkit.

### MOK enrollment (Secure Boot only)

With Secure Boot enabled, the driver modules are signed with a Machine Owner
Key. During install you set a one-time password; on the next reboot a blue
**"Perform MOK management"** screen appears **once**:

> **Enroll MOK** → **Continue** → **Yes** → type the password → **Reboot**

Skip it and the driver silently fails to load. If that happens, re-run
`sudo update-secureboot-policy --enroll-key` and reboot again.

### Verify after reboot

```bash
nvidia-smi                     # shows "GeForce RTX 5090 Laptop GPU" + driver version
prime-select query             # hybrid graphics mode: on-demand (default) / nvidia / intel
```

`on-demand` renders the desktop on the Intel iGPU (better battery) and runs
CUDA/games on the NVIDIA dGPU per-app (`__NV_PRIME_RENDER_OFFLOAD=1
__GLX_VENDOR_LIBRARY_NAME=nvidia <app>` forces offload). `sudo prime-select
nvidia` pins everything to the dGPU — useful when external monitors are wired
to it. The Raider also has a BIOS/MSI-Center MUX ("discrete mode") that
bypasses hybrid graphics entirely; Linux is happiest in the default hybrid
mode.

## 3.2 Kernel — `scripts/20-kernel.sh`

Ubuntu 26.04's stock kernel **is already 7.0**, so this script is a
verification step. It also offers:

- **HWE stack** (`linux-generic-hwe-26.04`): Canonical-signed newer kernels as
  point releases arrive (≈26.04.2 onward). Safe default — say yes.
- **Mainline builds** (kernel.ubuntu.com via the `mainline` tool): bleeding
  edge 7.x. These are **unsigned** (conflicts with Secure Boot) and can be
  newer than what NVIDIA's DKMS supports. Say no unless you're chasing a
  specific hardware fix.

## 3.3 Dev tools — `scripts/setup.sh`

Interactive: each component prompts y/n. Re-run any time; modules are
idempotent. `DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh` accepts everything for
an unattended run.

| Module | What you get | Method |
|---|---|---|
| Git | Latest stable git + git-lfs | git-core PPA (optional) |
| Claude Code | Anthropic's coding CLI | Official native installer (auto-updating; npm route is deprecated) |
| Docker | Engine + Buildx + Compose v2, docker group, NVIDIA Container Toolkit | Official Docker apt repo |
| JDK | Java 25 LTS | Ubuntu OpenJDK **or** Eclipse Temurin (Adoptium repo) |
| Maven | Pinned Apache Maven (see `config/versions.env`) | Apache dist tarball → `/opt/maven`, SHA-512 verified |
| C/C++ | GCC, Clang/LLVM, CMake, Ninja, gdb, valgrind, ccache | Ubuntu archive |
| Go | Latest stable (resolved from go.dev) | Official tarball → `/usr/local/go` |
| Rust | Stable toolchain + clippy + rustfmt | rustup |
| Elastic Stack | Elasticsearch + Kibana, **Basic license**, single node | Docker Compose (`~/elastic`), generated credentials |
| Ollama | Local LLM runtime, GPU-accelerated | Official install script |

Order notes handled for you: Docker before Elastic, JDK before Maven, and the
NVIDIA Container Toolkit / Ollama GPU support key off the driver from 3.1.

### After it finishes

```bash
exec bash -l                              # pick up PATH changes
docker run --rm hello-world               # docker group active? (else log out/in)
docker run --rm --gpus all ubuntu nvidia-smi   # GPU visible in containers
curl -sk -u elastic:<pw> https://localhost:9200/_license   # "type" : "basic"
ollama run llama3.2                       # first model on the 5090
```

Elastic credentials are generated into `~/elastic/.env`; Kibana is at
<http://localhost:5601> (user `elastic`). Both services bind to localhost
only.

Anything misbehaving → [troubleshooting](troubleshooting.md).

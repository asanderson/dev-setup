# dev-setup

Repeatable dual-boot + development environment setup for the
**MSI Raider 18 HX AI A2XWJG-069US**
(Intel Core Ultra 9 285HX · GeForce RTX 5090 Laptop GPU · 64GB DDR5-6400 ·
2TB NVMe SSD · 18" 120Hz), factory-installed with Windows 11 Pro.

End state: Windows 11 Pro **and** Ubuntu 26.04 LTS side by side, with

- **Linux kernel 7.0+** — Ubuntu 26.04's stock GA kernel is 7.0, verified by
  `scripts/20-kernel.sh` (with optional HWE/mainline paths to newer kernels);
- **Official NVIDIA driver** for the RTX 5090 Laptop GPU — Blackwell requires
  the *open* kernel modules (`nvidia-driver-580-open` or newer branch), with
  Secure Boot/MOK handled;
- an **interactive dev-tool installer** (each item individually prompted):
  Git, Claude Code, Docker, JDK (25 LTS), Maven, C/C++, Go, Rust,
  Elastic Stack (Basic license, in Docker), and Ollama.

## The path

| Step | Where | Doc |
|---|---|---|
| 1. Prepare Windows (BitLocker, fast startup, shrink disk, USB, BIOS keys) | Windows | [docs/01-windows-prep.md](docs/01-windows-prep.md) |
| 2. Install Ubuntu 26.04 alongside Windows | Ubuntu installer | [docs/02-ubuntu-install.md](docs/02-ubuntu-install.md) |
| 3. NVIDIA driver → kernel check → dev tools | Ubuntu | [docs/03-post-install.md](docs/03-post-install.md) |
| Anything broken | — | [docs/troubleshooting.md](docs/troubleshooting.md) |

## Quick start (on the freshly installed Ubuntu)

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/asanderson/dev-setup.git ~/dev-setup
cd ~/dev-setup

./scripts/10-nvidia-driver.sh   # NVIDIA driver + MOK guidance, then reboot
./scripts/20-kernel.sh          # verify kernel 7.0+, optional newer kernels
./scripts/setup.sh              # interactive: pick your dev tools
```

Unattended (accept every prompt): `DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh`

## Repo layout

```
docs/                    Step-by-step runbook (Windows prep → install → post-install)
scripts/
  10-nvidia-driver.sh    RTX 5090 Laptop GPU driver (open modules, Secure Boot aware)
  20-kernel.sh           Kernel 7.0+ verification, HWE / mainline options
  setup.sh               Interactive orchestrator for the modules below
  lib/common.sh          Shared helpers (prompts, apt, logging)
  modules/*.sh           One idempotent installer per tool
config/
  versions.env           Pinned versions for artifact-based installs
  elastic/               Docker Compose for Elasticsearch + Kibana (Basic license)
```

## Repeatability notes

- Modules are **idempotent** — re-run `setup.sh` any time; already-installed
  tools update or no-op.
- Artifact-based installs (Maven, Elastic) are **pinned** in
  `config/versions.env`; apt/rustup/go-based installs track their official
  channels. Bump the pins deliberately and re-run the module.
- Everything third-party comes from **official sources only**: vendor apt
  repos with GPG keyrings, checksummed tarballs, or vendor install scripts.

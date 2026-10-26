# Dev tools — `scripts/setup.sh`

Interactive development-environment installer for Ubuntu 26.04. Each
component prompts y/n; modules are idempotent and safe to re-run.
`DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh` accepts everything for an
unattended run.

Every component also has a command-line flag (`--git`, `--docker`,
`--opensearch`, ...; `./scripts/setup.sh --list` prints them all), and
`--modules git,docker,rust` takes a comma-separated list. Interactive runs
still confirm each component — the flags just pre-scope the menu; unattended
runs install exactly the selected components:

```bash
./scripts/setup.sh --docker --opensearch                     # offer only these two
DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --docker --opensearch   # install exactly these two
DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh                    # install everything
```

Selection order never matters: components always install in dependency
order (the NVIDIA driver and CUDA Toolkit first, Node.js/Python before the
agent CLIs that run on them, Docker before Elastic/OpenSearch, JDK before
Maven, the local-LLM runtimes last).

Windows-only components (Git Bash, Notepad++, WinSCP, Cygwin) and the
Windows builds of the rest come from the native Windows installer,
`scripts\setup.ps1` — see [Windows](#windows).

## Uninstalling

`scripts/uninstall.sh` mirrors the installer's selection contract: **all
components are candidates by default** — interactive runs confirm each one
(default yes), non-interactive runs (`DEV_SETUP_ASSUME_YES=1`) remove
exactly the command-line selection (`--modules LIST`, one `--<component>`
flag each), or everything with no flags. Components remove in reverse
dependency order (stacks before Docker, Maven before JDK), vendor repo
files are cleaned up, and `python3` is never removed (the OS depends on
it). **User data is kept by default** — container volumes and images,
`~/.m2`, `~/go`, `~/.kube`/`~/.aws`, VS Code settings, Ollama models,
Claude config — pass `--purge-data` to remove that too; every module logs
what it kept.

```bash
./scripts/uninstall.sh                          # confirm each component (default yes)
DEV_SETUP_ASSUME_YES=1 ./scripts/uninstall.sh --elastic --ollama
DEV_SETUP_ASSUME_YES=1 ./scripts/uninstall.sh --purge-data   # everything, data included
```

## Offline / air-gapped installs

`scripts/offline-bundle.sh --pack` builds a **self-contained archive** for
enclaves with no network (Ubuntu 26.04 amd64 targets). The
[SBOM](../sbom.cdx.json) is the component manifest: pinned versions come
from it, latest-resolved components are resolved once at pack time, and the
bundle records exactly what was packed (`MANIFEST.sha256` + a copy of the
SBOM as provenance). The apt dependency closure is computed in a **fresh
container**, so the bundle is complete for a clean machine regardless of
what the packing host has installed.

```bash
./scripts/offline-bundle.sh --pack                      # all offline-packagable components
./scripts/offline-bundle.sh --pack --modules git,python,cloud
# → dev-setup-offline-<date>.tar.gz  (transfer into the enclave, untar, then:)
./dev-setup-offline-<date>/install-offline.sh           # verifies checksums, installs; no network, no repo
```

Offline-packagable: git (archive, no PPA), vscode + extensions (.vsix),
docker, podman, jdk, maven, cpp (+ LLVM), golang, rust (standalone
installer), python, cloud (k3s air-gap procedure with preloaded images,
Helm, k9s, Ansible wheels, AWS CLI), elastic + opensearch (saved container
images + compose configs), ollama, and ollama-models — the model weights
themselves, pulled at pack time inside the official Ollama container and
shipped as a portable blobs+manifests store, **with the pinned-context
variants already built** so the enclave needs no daemon to recreate them.
That adds ~50GB, so scope the pack with `--modules` when you don't need
them; selecting it automatically pulls in `ollama` for the runtime.
**Not packagable** — network services that cannot function in an enclave:
claude-code (+ plugins), the proton-* apps, the hosted-model agent CLIs
(codex, opencode, oh-my-pi, hermes-agent, openclaw) and the Amazon
WorkSpaces client. **Not yet packaged**: nodejs, the GPU stack
(nvidia-driver, cuda-toolkit, llama-cpp, ik-llama-cpp, koboldcpp,
ktransformers, vllm), strata, 7zip, libreoffice and vmware-workstation.

## Container image

`scripts/build.sh` runs the installer **inside an image build** and produces
an OCI-compliant container image of the selected components — the same
selection contract as the installer (`--modules LIST`, one `--<component>`
flag each, everything imageable with no flags; `--list` prints the set).
The image is the target OS's base image — `--os
ubuntu|debian|pureos|rocky|rhel`, default ubuntu (26.04); PureOS builds on
the byzantium base, the only OCI image Purism publishes — with the
components installed by the same modules, as the non-root user `dev`
(uid 1000). Build with Docker (default) or Podman via `--engine`, and name
the result with `--tag` (default `dev-setup:latest`).

Not imageable, by design: **docker and podman** (they are the engines that
run this image, not image content), **elastic/opensearch** (their installs
need a running Docker daemon — run those stacks beside the container
instead), **proton-vpn** (its daemon's postinst needs a running
systemd, and a VPN belongs on the host, not in a container image),
**ollama-models** and the rest of the **GPU stack** (nvidia-driver is a
host kernel driver; cuda-toolkit, llama-cpp, ik-llama-cpp, koboldcpp,
ktransformers and vllm are multi-GB, GPU-bound builds and wheels),
**vmware-workstation** (a host hypervisor with kernel modules), and the
**libreoffice / amazon-workspaces** desktop apps. The agent CLIs (codex,
opencode, oh-my-pi, hermes-agent, openclaw, strata) and 7zip are
imageable.

Per-OS image exclusions (base-image realities, not module choices):
**proton-authenticator** drops out of the rocky/rhel/pureos images (its
webkit dependency is absent from EL9 repos and the byzantium base), and
the **rhel** image — built on Red Hat's UBI, whose unentitled repos carry
no GUI stacks — also drops vscode and the Proton desktop apps; install
those on a subscribed RHEL host with setup.sh directly.

The **publish-images workflow** (`.github/workflows/publish-images.yml`,
manual trigger) builds the full-component image for every target OS and
pushes each to a container registry — by default
`ghcr.io/asanderson/dev-setup:<os>` as the moving alias plus a
version-specific `:<os>-<version>` tag read from the image's own
os-release (e.g. `ubuntu-26.04`, `debian-13`, `rocky-9.3`), and `:latest`
for ubuntu — which the workflow's own token can push to; the `registry`
input redirects to another namespace (e.g. Google Artifact Registry once
its credentials are configured as repo secrets).

`scripts/run.sh` runs the image. It prompts interactively — or takes flags
for non-interactive runs — for **which user to run as** (the user who
executed the script is the default; a local name resolves to its uid:gid,
`dev` — the image's built-in user — maps to uid 1000, or pass `UID[:GID]`
directly) and **which local directories to mount**
(each appears at the same path inside the container). Anything after `--`
runs instead of the default login shell.

```bash
./scripts/build.sh --modules git,python,cloud --tag dev-setup:cloud
./scripts/run.sh --image dev-setup:cloud                # prompts for user + mounts
DEV_SETUP_ASSUME_YES=1 ./scripts/run.sh --image dev-setup:cloud \
  --user "$(id -un)" --mount ~/projects -- bash -lc 'git --version'
```

Corporate/CONNECT proxies: `https_proxy`/`no_proxy` pass through as build
args, and `DEV_SETUP_CA_BUNDLE=<path>` injects a proxy CA for the build
(removed from the final image).

## Target operating systems

Interactive runs prompt for the target OS; non-interactive runs take
`--os` — the **default is `ubuntu`** either way, the platform every module
is written and tested for. Catalog: `ubuntu debian pureos rocky rhel qubes
windows`. The installer configures the machine it runs on, so it verifies
`/etc/os-release` matches the declared target before installing anything;
`qubes` is in the catalog for honest guidance (use a Debian-template qube
with `--os debian`) rather than installs; `windows` points at the native
Windows installer, [`scripts\setup.ps1`](#windows) (and at WSL2 Ubuntu with
`--os ubuntu` for this Linux toolchain).

Components whose installer can't work on the target OS are **warned
about**: unattended runs never install them; interactive runs may force one
(default no). Support follows each module's package sources, as written:

Almost every component now installs on **every target OS**, dispatching per
family to the right installer and packages — apt vs dnf, vendor `.deb` vs
`.rpm`, Microsoft's apt vs yum repos:

| Supported on | Components | How |
|---|---|---|
| Everywhere (all five) | Git, Node.js (+ Bun), C/C++, VS Code, JDK, Python, Cloud tools, Podman, Claude Code (+ plugins), Maven, Go, Rust, Ollama (+ its coding models), Elastic, OpenSearch, Proton Mail/Bridge/Drive CLI/Pass/Meet | distro packages per family (git-core PPA extra on Ubuntu; newest-LLVM extra on Ubuntu/Debian, where apt.llvm.org has suites); Microsoft's apt/yum repos; Proton's `.deb`/`.rpm` builds; distro-agnostic installers and tarballs |
| Ubuntu, Debian, Rocky, RHEL (no PureOS) | Docker | Docker's official repos: apt suites for Ubuntu/Debian, dnf repos for centos(Rocky)/RHEL — no PureOS suite exists; use Podman there |
| Debian family only (ubuntu, debian, pureos) | Proton VPN | Proton's official Linux VPN app ships apt packages only — no Enterprise Linux channel exists |
| Debian family only (ubuntu, debian, pureos) | Proton Authenticator | its package needs libwebkit2gtk-4.1, which EL9 repos don't provide (verified against Rocky 9's full repo set) |
| Everywhere (all five) | Codex, OpenCode, Oh My Pi, Hermes Agent, OpenClaw, Strata, 7-Zip, LibreOffice, VMware Workstation Pro, llama.cpp, ik_llama.cpp, KoboldCpp | vendor install scripts and static binaries (distro-agnostic), the 7-Zip vendor tarball, distro LibreOffice packages, Broadcom's distro-agnostic `.bundle`, source builds |
| Ubuntu, Debian, Rocky, RHEL (no PureOS) | NVIDIA GPU driver, CUDA Toolkit, vLLM | NVIDIA publishes no driver/CUDA channel for PureOS (a free-software-only distro); vLLM's CUDA wheels need that driver |
| Ubuntu and Debian only | KTransformers | its wheels are `manylinux_2_35` — glibc 2.35+; EL9 ships 2.34 |
| Ubuntu only | Amazon WorkSpaces client | Amazon's apt repo has suites for the Ubuntu LTS releases it supports (20.04, 22.04, 24.04) — no Debian/EL client. **Ubuntu 26.04 has none yet** (the 24.04 build needs libicu74/libxml2, which 26.04 dropped), so there the module refuses with guidance: use WorkSpaces Web Access or the Windows client until Amazon publishes one |
| Windows only (`scripts\setup.ps1`) | Git Bash, Notepad++, WinSCP, Cygwin | Windows software by definition — see [Windows](#windows) |

> **GPU note:** if this machine has an NVIDIA GPU, install the driver first —
> the NVIDIA Container Toolkit and Ollama acceleration key off it. For the
> MSI Raider 18 dual-boot machine that runbook lives in
> [asanderson/dual-boot](https://github.com/asanderson/dual-boot).

| Module | What you get | Method |
|---|---|---|
| Git | Latest stable git + git-lfs | git-core PPA (optional) |
| Node.js | nvm (latest) managing Node — latest LTS + npm installed via `nvm install --lts` — plus yarn/pnpm via corepack and Bun (latest); Claude Code's JS tooling runs on these | nvm + Bun official installers, per-user (~/.nvm, ~/.bun) — no system packages, identical on every target |
| Claude Code | Anthropic's coding CLI | Official native installer (auto-updating; npm route is deprecated) |
| Claude Code plugins | superpowers, caveman, karpathy-skills, ecc, claude-mem, agentic-awesome-skills, gsd-core — latest releases | `claude plugin` marketplaces (each plugin's GitHub repo) |
| VS Code | Visual Studio Code, stable channel + curated extensions (Claude Code, Codex, Python, C/C++, Java, rust-analyzer, Ansible, YAML, Go, CodeLLDB, Remote Development/Explorer/SSH-edit, Kubernetes, Docker, AWS Toolkit, GitHub Repositories, GitLab, gitignore, GitLens) | Microsoft apt repo; extensions from the VS Code Marketplace at the newest compatible version |
| Docker | Engine + Buildx + Compose v2, docker group, NVIDIA Container Toolkit | Official Docker repos (apt on Ubuntu/Debian; dnf on Rocky/RHEL) |
| Podman | Rootless, daemonless containers **running as your user** — the Docker alternative; coexists with Docker (skip the `podman-docker` shim if both) | Ubuntu/Debian archives; native dnf package on Rocky/RHEL |
| JDK | Java 25 LTS | Ubuntu OpenJDK **or** Eclipse Temurin (Adoptium repo) |
| Maven | Pinned Apache Maven (see `config/versions.env`) | Apache dist tarball → `/opt/maven`, SHA-512 verified |
| C/C++ | GCC, Clang/LLVM, CMake, Ninja, gdb, valgrind, ccache — plus the newest Clang/LLVM release as versioned `clang-N` packages | Ubuntu archive + official apt.llvm.org repo |
| Go | Latest stable (resolved from go.dev) | Official tarball → `/usr/local/go` |
| Rust | Stable toolchain + clippy + rustfmt | rustup |
| Python | Python 3 + venv, pip, dev headers, pipx | Ubuntu archive |
| Cloud | k3s (+ bundled kubectl), Helm, k9s, Ansible, AWS CLI v2 — latest stable releases | Official k3s/Helm install scripts; k9s from its GitHub releases; Ansible from PyPI via pipx; AWS CLI official bundle |
| Proton VPN | Official GNOME desktop app (CLI available) | Proton's apt repo (bootstrap .deb sha256-pinned against Proton's published checksum) |
| Proton Mail | Desktop app, **bundles Proton Calendar** (no standalone Linux Calendar app exists) | Official latest-version .deb; app self-updates |
| Proton Bridge | IMAP/SMTP bridge for mail clients (paid plans) | Official .deb from Proton's version feed, **GPG-signature-verified**; self-updates |
| Proton Drive | **CLI** (Proton ships no Linux GUI app for Drive yet) | Official static binary from Proton's version feed, SHA512-verified |
| Proton Pass | Password manager desktop app | Official latest-version .deb; app self-updates |
| Proton Meet | E2E-encrypted videoconferencing desktop app | Official latest-version .deb; app self-updates |
| Proton Authenticator | TOTP two-factor app | Official latest-version .deb; app self-updates |
| Elastic Stack | Elasticsearch + Kibana, **Basic license**, single node | Docker Compose (`~/elastic`), generated credentials |
| OpenSearch | OpenSearch + Dashboards, **Apache-2.0, no license tiers** — the Elastic alternative (OpenSearch Software Foundation / Linux Foundation), single node | Docker Compose (`~/opensearch`), generated credentials |
| Ollama | Local LLM runtime, GPU-accelerated | Official install script |
| Ollama coding models | The verified local coding stack — gpt-oss 20B (MXFP4), Gemma 4 26B MoE (QAT), Laguna XS 2.1 — each pulled and given a **pinned-context variant**, plus the serving config (flash attention, q8_0 KV) those contexts depend on. ~50GB. `DEV_SETUP_OLLAMA_NEMOTRON=1` adds Nemotron 3 Nano at IQ4_XS from Hugging Face | `ollama pull` + generated Modelfiles |
| NVIDIA GPU driver | Open kernel modules (the only flavor for Blackwell/RTX 50; NVIDIA ships only those from R615). Skips cleanly when no NVIDIA GPU is present; reboot afterwards. The MSI Raider's full runbook (kernel, Secure Boot) stays in [asanderson/dual-boot](https://github.com/asanderson/dual-boot) | Ubuntu: `ubuntu-drivers install` (recommended branch, Canonical-signed); Debian/Rocky/RHEL: `nvidia-open` from NVIDIA's CUDA repo (Debian's own packages stop at 550, pre-Blackwell) |
| CUDA Toolkit | nvcc + CUDA libraries, latest release, under `/usr/local/cuda` (PATH via `/etc/profile.d/cuda.sh`); works without a GPU | NVIDIA's CUDA network repo (`cuda-toolkit` meta-package) |
| Codex | OpenAI's coding agent CLI (`codex`) | OpenAI's standalone installer (static musl build; GitHub release fallback) |
| OpenCode | Open-source terminal coding agent (`opencode`), v2 | Official install script → `~/.opencode/bin`, linked into `~/.local/bin` |
| Oh My Pi | `omp`, the batteries-included fork of the Pi coding agent | Official install script (`bun install -g` with the nodejs module's Bun, else a verified binary) |
| Hermes Agent | Nous Research's agent CLI (`hermes`) | Official install script, non-interactive (own pinned uv/Python under `~/.hermes`) |
| OpenClaw | Self-hosted AI assistant gateway (`openclaw`); onboarding left to you, with the upstream security guidance printed | Official install script, npm method, into the nvm-managed Node (needs the nodejs module) |
| Strata | Local LLM app + engine with OpenAI/Anthropic-compatible APIs on localhost ([Niko1221/Strata](https://github.com/Niko1221/Strata)); `strata connect` wires Claude Code/Codex/OpenCode to it | Official installer at the `STRATA_VERSION` pin — the script SHA-256 verified, and pointed at the same release, whose manifest it checks the Terminal archive against |
| 7-Zip | `7zz` (+ a `7z` alias), pinned in `config/versions.env` | Igor Pavlov's GitHub releases (ip7z/7zip), SHA-256 verified; the static build, identical on every target |
| LibreOffice | Office suite | Distro packages (AppStream on EL — deprecated in RHEL 9.5, supported through RHEL 9) |
| VMware Workstation Pro | Desktop hypervisor — **17 Pro as requested, or the successor bundle you supply** (17.6.4 is the last 17.x; end of service Nov 2025, and 26H1 is the first release supporting Ubuntu 26.04 hosts). Broadcom downloads need a free support-portal login: download the `.bundle`, then run with `DEV_SETUP_VMWARE_BUNDLE=/path/to/it` — it runs as root, so it is never picked up implicitly — and `DEV_SETUP_VMWARE_BUNDLE_SHA256=<portal checksum>` to have it verified first (otherwise its SHA-256 is printed for you to compare) | Broadcom's `.bundle` run unattended (`--console --eulas-agreed --required`) + `vmware-modconfig` builds vmmon/vmnet |
| Amazon WorkSpaces | WorkSpaces client (`workspacesclient`) on the Ubuntu releases Amazon publishes a suite for (20.04–24.04); refused with guidance on 26.04 until Amazon ships one | Amazon's apt repo |
| llama.cpp | `llama-cli`, `llama-server`, ... built from the newest release (`LLAMA_CPP_VERSION` pins a tag) — CUDA when the toolkit is present, tuned to the local GPU | Source build (static) → `~/.local/opt/llama.cpp`, linked into `~/.local/bin` |
| ik_llama.cpp | ikawrakow's fork (extra quant types, faster CPU/hybrid MoE), head of `main` — binaries as `ik-llama-*` so both forks coexist | Source build (static) → `~/.local/opt/ik_llama.cpp` |
| KoboldCpp | Single-file GGUF runner + web UI (`koboldcpp`, port 5001), newest release | Release binary: the CUDA build with an NVIDIA GPU, `nocuda` otherwise |
| KTransformers | CPU/GPU hybrid inference for huge MoE models: `kt-kernel` + the `sglang-kt` SGLang fork + the `kt` CLI | PyPI into a uv virtualenv (`~/.local/opt/ktransformers`); upstream lists SM 80–90 GPUs, RTX 50 not yet |
| vLLM | High-throughput OpenAI-compatible serving (`vllm serve`), newest release; needs an NVIDIA driver (R580+ for the CUDA 13 wheels), no toolkit | PyPI into a uv virtualenv (`~/.local/opt/vllm`), PyTorch backend via `--torch-backend=auto` |

Pick Elastic, OpenSearch, or both — the OpenSearch stack's ports are offset
(9201 REST, 5602 Dashboards) so the two dev stacks coexist.

Order notes handled for you: Docker before Elastic/OpenSearch, JDK before Maven, and
GPU-dependent pieces detect the driver at runtime (with a `sudo docker`
fallback when fresh `docker`-group membership hasn't reached the current
session yet).

## Windows

`scripts/setup.ps1` is the native Windows installer (Windows PowerShell 5.1
or PowerShell 7) for every component this repo supports on Windows. Same
selection contract as `setup.sh`: interactive runs confirm each component
(default yes), `--<component>` flags or `-Modules a,b` pre-scope the menu,
and unattended runs (`-AssumeYes` or `DEV_SETUP_ASSUME_YES=1`) install
exactly the selection — or everything. Installs are idempotent (winget
upgrades in place or no-ops). `scripts/uninstall.ps1` mirrors
`uninstall.sh` (reverse order, user data kept unless `-PurgeData`).

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1                     # confirm each
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 --7zip --winscp     # offer only these
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 -AssumeYes -Modules git-bash,notepad-plus-plus
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 --cygwin -PurgeData
```

Run it from an elevated PowerShell to avoid one UAC prompt per machine-wide
package; winget itself ships with Windows 10/11 as "App Installer".

| Component | Windows source |
|---|---|
| CUDA Toolkit | winget `Nvidia.CUDA` |
| Git Bash | winget `Git.Git` (Git for Windows: git, git-lfs, Git Bash) |
| Codex | OpenAI's `install.ps1` |
| OpenCode | npm `@opencode/cli` (Node.js LTS pulled in from winget `OpenJS.NodeJS.LTS` when missing) |
| Oh My Pi | `omp.sh/install.ps1` |
| Hermes Agent | Nous Research's `install.ps1 -NonInteractive` |
| OpenClaw | `openclaw.ai/install.ps1 -NoOnboard` |
| Strata | the pinned release's `install.ps1` (SHA-256 verified, same `STRATA_VERSION` pin as Linux — read from `config/versions.env`) |
| 7-Zip | winget `7zip.7zip` |
| Notepad++ | winget `Notepad++.Notepad++` |
| WinSCP | winget `WinSCP.WinSCP` |
| Cygwin | winget `Cygwin.Cygwin` (base install at `C:\cygwin64`; Cygwin has no uninstaller, so removal deletes that root only with `-PurgeData`) |
| LibreOffice | winget `TheDocumentFoundation.LibreOffice` |
| VMware Workstation Pro | the installer you downloaded from Broadcom's portal, given as `DEV_SETUP_VMWARE_INSTALLER=<path>` (never picked up implicitly — it runs elevated), checked for a valid VMware/Broadcom Authenticode signature, then run silently with `EULAS_AGREED=1` — winget dropped the package when Broadcom gated the downloads |
| Amazon WorkSpaces | winget `Amazon.WorkspacesClient` |
| llama.cpp | winget `ggml.llamacpp` (the Vulkan release build — runs on NVIDIA, AMD and Intel GPUs) |
| KoboldCpp | the newest release's `koboldcpp.exe` (CUDA) or `koboldcpp-nocuda.exe` → `%LOCALAPPDATA%\Programs\koboldcpp`, on the user PATH |

Linux-only, warned about and skipped on Windows: **NVIDIA GPU driver**
(NVIDIA publishes no winget or scriptable driver package — use the NVIDIA
App or Windows Update), **ik_llama.cpp** (no Windows releases),
**KTransformers** and **vLLM** (Linux-only) — run those under WSL2 Ubuntu
with `setup.sh --os ubuntu`. On Linux, `setup.sh --os windows` points here.

## After it finishes

```bash
exec bash -l                              # pick up PATH changes
docker run --rm hello-world               # docker group active? (else log out/in)
docker run --rm --gpus all ubuntu nvidia-smi   # GPU visible in containers
curl -s -u elastic:<pw> http://localhost:9200/_license    # "type":"basic"
curl -sk -u admin:<pw> https://localhost:9201             # OpenSearch (demo TLS cert, hence -k)
ollama run llama3.2                       # first model
nvidia-smi                                # after the nvidia-driver module + reboot
nvcc --version                            # CUDA Toolkit
llama-server -hf <user>/<repo>:<quant>    # llama.cpp, OpenAI-compatible API
codex / opencode / omp / hermes setup     # agent CLIs: sign in or point at a local server
```

Elastic credentials are generated into `~/elastic/.env` (mode 600); Kibana is
at <http://localhost:5601> (user `elastic`). OpenSearch credentials likewise
land in `~/opensearch/.env`; Dashboards is at <http://localhost:5602> (user
`admin`). All four services bind to localhost only.

Anything misbehaving → [troubleshooting](troubleshooting.md).

# Research notes — verified facts behind this runbook

Produced by a multi-agent deep-research pass (August 17, 2026): 5 search
angles → 25 sources fetched → 116 claims extracted → the 25 most
load-bearing claims put through 3-vote adversarial verification. **All 25
were confirmed (0 refuted).** Claims outside that budget are marked below as
unverified. Version numbers move monthly — re-check exact point releases at
install time.

## Ubuntu 26.04 LTS & Linux kernel 7.0 — verified

- **Ubuntu 26.04 LTS "Resolute Raccoon"** was released **April 23, 2026**,
  supported until **April 2031** (ten years with Ubuntu Pro ESM); the 26.04.1
  point release shipped August 6, 2026.
  ([release notes](https://documentation.ubuntu.com/release-notes/26.04/),
  [announce](https://lists.ubuntu.com/archives/ubuntu-announce/2026-April/000323.html),
  [Canonical blog](https://canonical.com/blog/canonical-releases-ubuntu-26-04-lts-resolute-raccoon))
- **Linux kernel 7.0 is real and is 26.04's stock GA kernel.** Linus Torvalds
  announced in the 6.19 release notes that the next kernel would be **7.0**
  (there is no 6.20); 7.0 released ~April 12, 2026, eleven days before Ubuntu
  26.04. The renumbering is bookkeeping, not a technical break. The HWE stack
  on 26.04 is currently also 7.0.
  ([release notes](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/):
  "the Linux kernel has been updated from version 6.8 to 7.0";
  [Ubuntu kernel team](https://discourse.ubuntu.com/t/26-04-lts-resolute-raccoon-shipping-with-the-final-7-0-linux-kernel/80838),
  [Phoronix](https://www.phoronix.com/news/Linux-7.0-Is-Next))
  → **Consequence: a stock 26.04 install satisfies "kernel 7.0 or newer" with
  no extra work.**
- **Newer-than-7.0 kernels** (7.1.x/7.2-rc live on
  [kernel.ubuntu.com/mainline](https://kernel.ubuntu.com/mainline/) as of
  Aug 14, 2026) are explicitly **unsupported, get no security updates, are
  not Secure Boot-signed, and NVIDIA DKMS modules are not expected to build
  against them**
  ([Ubuntu wiki](https://wiki.ubuntu.com/Kernel/MainlineBuilds)). The
  supported path to newer kernels is the HWE stack at later point releases.

## NVIDIA RTX 5090 Laptop GPU on Linux — verified

- **Open kernel modules are mandatory for Blackwell.** NVIDIA: open modules
  are the default since the 560 series (Turing+), and "for cutting-edge
  platforms such as … NVIDIA Blackwell, you must use the open-source GPU
  kernel modules. The proprietary drivers are unsupported."
  ([driver install guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/kernel-modules.html),
  [NVIDIA blog](https://developer.nvidia.com/blog/nvidia-transitions-fully-towards-open-source-gpu-kernel-modules.md/))
- **R595 is the current production branch** (595.58.03 released Mar 24, 2026,
  marked Recommended/non-beta; 595.91.07 latest as of Aug 17, 2026; 610.57.04
  is the new-feature branch). The 595 README's supported-chips list includes
  **"NVIDIA GeForce RTX 5090 Laptop GPU" (device 2C18)**, and Ubuntu 26.04
  ships an official 595 driver package.
  ([driver page](https://www.nvidia.com/en-us/drivers/details/265870/),
  [supported chips](https://download.nvidia.com/XFree86/Linux-x86_64/595.58.03/README/supportedchips.html),
  [latest.txt](https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt))
- **Known issue:** RTX 50-series s2idle resume hangs reported on kernel 7.0
  (NVIDIA open-gpu-kernel-modules tracker) — see
  [troubleshooting](troubleshooting.md#suspendresume-hangs-rtx-50-series--kernel-70).

## Dev toolchain on Ubuntu 26.04 — verified

- **Docker Engine officially supports Ubuntu 26.04** ("Resolute" is listed
  and the apt repo serves a live `resolute` dist); current documented method
  is the key at `/etc/apt/keyrings/docker.asc` + a **deb822
  `docker.sources`** file; Engine packages are in the 5:29.x series.
  ([Docker docs](https://docs.docker.com/engine/install/ubuntu/),
  [repo dists](https://download.docker.com/linux/ubuntu/dists/))
- **Claude Code**: recommended install is the native installer
  `curl -fsSL https://claude.ai/install.sh | bash`; supports Ubuntu 20.04+.
  The npm path installs the same native binary but requires Node.js 22+
  (npm version 2.1.233 at verification time).
  ([setup docs](https://code.claude.com/docs/en/setup))
- **Temurin 25 is the current JDK LTS** (GA 2025-09-22; 25.0.4 released
  2026-08-04; next LTS lands Sept 2027) via `packages.adoptium.net`
  (`temurin-25-jdk`). Caveat: a brand-new Ubuntu codename may need a
  fallback to a listed suite (e.g. `noble`) until Adoptium adds it — the JDK
  module does this automatically.
  ([Adoptium docs](https://adoptium.net/installation/linux))
- **Go**: official tarball into `/usr/local/go` (removing any prior tree
  first — "Do not untar the archive into an existing /usr/local/go tree").
  ([go.dev/doc/install](https://go.dev/doc/install))
- **Rust**: rustup one-liner remains the project's recommended method
  (rustup 1.30, July 2026). ([rustup.rs](https://rustup.rs/),
  [rust-lang.org](https://www.rust-lang.org/tools/install))
- **Ollama**: official script `curl -fsSL https://ollama.com/install.sh | sh`
  (binary + systemd service, API on 127.0.0.1:11434); the NVIDIA driver is
  installed separately and verified with `nvidia-smi`.
  ([Ollama docs](https://docs.ollama.com/linux))

## Elastic Stack — verified

- **Elastic Stack 9.5.1 is the latest 9.x** (tag v9.5.1 published Aug 11,
  2026) and is the version in Elastic's official Docker Compose docs
  (`STACK_VERSION=9.5.1`, images from `docker.elastic.co`).
  ([compose docs](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-compose),
  [release](https://github.com/elastic/elasticsearch/releases/tag/v9.5.1))
- The Basic-license setting (`xpack.license.self_generated.type=basic`) and
  `vm.max_map_count≥262144` were **not re-verified as standalone claims**,
  but both are long-standing requirements in Elastic's own
  [license-settings](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/license-settings)
  and
  [vm.max_map_count](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/vm-max-map-count)
  documentation (fetched during research; `basic` is the default
  self-generated license type).

## Unverified — treat as best practice, confirm on the machine

The MSI Raider 18 HX AI-specific claims didn't make the verification budget,
so the corresponding runbook steps rest on MSI support documentation,
community reports for this laptop family, and general dual-boot practice —
not adversarially verified sources:

- BIOS hotkeys (Del/F7/F11) — from
  [MSI's support note](https://www.msi.com/support/technical_details/MB_OS_Inst_HDDSSD_Unrecog).
- Whether the 2TB NVMe ships in Intel VMD/RAID mode and hides from the
  installer (reported on the same-generation
  [MSI Vector 16 HX AI](https://trail.t.u-tokyo.ac.jp/blog/25-06-28-dualboot-setup/)
  and [Ubuntu forum threads](https://discourse.ubuntu.com/t/dual-boot-installation-on-msi-laptop/65553));
  the safe-mode AHCI switch procedure is standard practice.
- BitLocker suspension, fast-startup, MOK enrollment flow — standard Ubuntu
  dual-boot practice; not model-specific.
- Killer BE1750 (Wi-Fi 7) — iwlwifi support since kernel 6.5 per
  [Intel community reports](https://community.intel.com/t5/Wireless/iwlwifi-issue-with-Intel-R-Killer-TM-Wi-Fi-7-BE1750-and-Ubuntu/td-p/1587301);
  full MLO/6GHz behavior on kernel 7.0 unconfirmed.
- Which exact driver `ubuntu-drivers` recommends on 26.04 for this GPU
  (595-open expected — the script honors whatever it recommends), and the
  current CUDA toolkit pairing for R595.

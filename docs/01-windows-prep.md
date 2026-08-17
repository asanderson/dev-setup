# Step 1 — Prepare Windows 11 Pro (do this first, on the Raider)

Target machine: **MSI Raider 18 HX AI A2XWJG-069US** (Core Ultra 9 285HX,
RTX 5090 Laptop GPU, 64GB DDR5-6400, 2TB NVMe SSD) with preinstalled
Windows 11 Pro.

Everything in this step happens inside Windows **before** you boot the Ubuntu
installer. Budget ~30–45 minutes plus update time.

## 1.1 Update Windows and firmware

1. Settings → Windows Update → install everything, reboot until clean.
2. Open **MSI Center** → Support → Live Update → install any **BIOS/EC
   firmware** updates. Newer firmware improves Linux compatibility on this
   platform (Arrow Lake-HX + Blackwell are recent silicon).

## 1.2 Save your BitLocker recovery key, then suspend BitLocker

Windows 11 Pro on this machine typically ships with BitLocker (or "Device
Encryption") enabled. Firmware-setting changes and repartitioning can trip
BitLocker recovery — have the key *before* touching anything.

1. Sign in at <https://account.microsoft.com/devices/recoverykey> and confirm
   a recovery key exists for this PC. Print it or store it off-machine.
2. Control Panel → **BitLocker Drive Encryption** → **Suspend protection**
   (or PowerShell as admin: `Suspend-BitLocker -MountPoint C: -RebootCount 3`).
   Suspension survives the next few reboots and re-arms automatically.

> Do **not** skip this. A BIOS storage-mode change with BitLocker armed will
> dump you into the 48-digit recovery prompt.

## 1.3 Disable Fast Startup (and don't hibernate)

Fast Startup keeps the NTFS filesystem in a half-shutdown state, which blocks
Linux from mounting the Windows partition safely and can corrupt data.

1. Control Panel → Power Options → *Choose what the power buttons do* →
   *Change settings that are currently unavailable* → untick **Turn on fast
   startup** → Save.
2. Or as admin: `powercfg /h off` (disables hibernation, which implies fast
   startup off).

## 1.4 Shrink the Windows partition

Free up space for Ubuntu on the 2TB SSD. **500 GB** is a comfortable split for
a dev machine (Docker images, Ollama models, and toolchains add up fast);
**150 GB** is a workable minimum.

1. Win+X → **Disk Management** → right-click **C:** → **Shrink Volume…**
2. Enter the amount to shrink (e.g. `512000` MB ≈ 500 GB) → Shrink.
3. Leave the freed space **unallocated** — the Ubuntu installer will use it.

If Windows won't shrink far enough (immovable files), run `defrag C: /X` and
temporarily disable the pagefile, then retry.

## 1.5 Create the Ubuntu 26.04 LTS install USB

On any machine, with an 8GB+ USB stick (it will be erased):

1. Download the **Ubuntu 26.04 LTS desktop** ISO from
   <https://ubuntu.com/download/desktop> and verify its SHA-256 against the
   published checksum.
2. Write it with [Rufus](https://rufus.ie) (Windows; GPT + UEFI target) or
   [balenaEtcher](https://etcher.balena.io) (any OS).

## 1.6 Know your BIOS keys (MSI)

| Action | Key (press repeatedly at the MSI logo) |
|---|---|
| BIOS setup | **Del** (then **F7** toggles Advanced mode) |
| One-time boot menu | **F11** |

> These keys come from MSI's support documentation and community reports for
> this laptop family, but were not independently verified on the A2XWJG
> specifically — if one doesn't respond, try the other, or use Windows:
> Settings → System → Recovery → Advanced startup → *UEFI Firmware Settings*.

Recommended BIOS settings for the install (Del → F7 Advanced):

- **Secure Boot: leave enabled.** Ubuntu 26.04 boots fine under Secure Boot,
  and the NVIDIA driver is handled by signed MOK enrollment
  (see [Step 3](03-post-install.md)). Only disable it if you later choose
  unsigned mainline kernels.
- **Fast Boot: disable** (BIOS setting, distinct from Windows Fast Startup) so
  the F11/Del keys are reliably caught.
- **Storage / VMD**: leave as-is for now. Only change it if the Ubuntu
  installer cannot see the SSD — see the VMD procedure in
  [troubleshooting](troubleshooting.md#installer-cannot-see-the-2tb-ssd-intel-vmdraid),
  because flipping it carelessly makes *Windows* unbootable.

Done? Continue to [Step 2 — Install Ubuntu](02-ubuntu-install.md).

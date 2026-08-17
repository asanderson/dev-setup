# Troubleshooting

## Installer cannot see the 2TB SSD (Intel VMD/RAID)

MSI ships this platform with the storage controller in **Intel VMD/RAID**
mode, which can hide the NVMe drive from the Ubuntu installer. The fix is
switching to **AHCI** — but doing that cold makes *Windows* unbootable, so
follow this exact order:

1. **In Windows:** suspend BitLocker (see Step 1.2), then set Windows to boot
   into Safe Mode once — admin prompt:
   `bcdedit /set {current} safeboot minimal` — and shut down.
2. **In BIOS** (Del at the MSI logo, F7 for Advanced): find the storage/VMD
   setting (often *Advanced → Integrated Peripherals → VMD Setup Menu →
   Enable VMD controller*) and set it to **Disabled** (AHCI). Save & exit.
3. **Windows boots into Safe Mode** — this is what re-detects the AHCI driver.
   In an admin prompt: `bcdedit /deletevalue {current} safeboot`, reboot, and
   confirm Windows starts normally.
4. Re-boot the Ubuntu USB — the SSD is now visible. Continue Step 2.

## Wi-Fi adapter missing

The Killer BE1750 (Intel BE200-class Wi-Fi 7) needs `iwlwifi` firmware from a
current `linux-firmware`. On 26.04:

```bash
sudo apt update && sudo apt full-upgrade -y     # pulls newest linux-firmware
sudo dmesg | grep -i iwlwifi                    # look for firmware load errors
```

A missing-firmware error naming `iwlwifi-gl-*.ucode`/`.pnvm` means
linux-firmware is stale — upgrade (above) or temporarily use USB tethering /
Ethernet to do so. Bluetooth on the same module follows the Wi-Fi firmware.

## `nvidia-smi` fails after driver install

- `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA
  driver` right after install → you rebooted **without enrolling the MOK**.
  Run `sudo update-secureboot-policy --enroll-key`, reboot, and complete the
  blue MOK screen (Enroll MOK → Continue → Yes → password).
- Check what's loaded: `lsmod | grep nvidia`; check DKMS build status:
  `dkms status`. A DKMS build failure against a very new mainline kernel means
  the kernel is ahead of the driver — boot the stock 7.0 kernel from GRUB's
  *Advanced options* menu.
- Confirm you have the **open** module variant (required for Blackwell):
  `dpkg -l | grep nvidia-driver` should show `nvidia-driver-XXX-open`.

## Black screen booting the installer or the installed system

Boot with `nomodeset`: in GRUB press `e`, append `nomodeset` to the `linux`
line, F10. Then (re-)install the NVIDIA driver, which removes the need for it.
Don't leave `nomodeset` permanently — it disables GPU acceleration.

## GRUB doesn't show Windows / machine boots straight to Windows

- Boots straight to **Windows**: firmware boot order — BIOS (Del) → Boot →
  put **ubuntu** first, or one-time via F11. In Windows, *Fast Startup* being
  re-enabled by an update can also grab the boot path; re-disable it.
- GRUB shows no **Windows Boot Manager** entry:

```bash
sudo os-prober                                   # should print the Windows EFI path
echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
sudo update-grub
```

- Windows entry boots to BitLocker recovery: normal after firmware changes —
  enter the recovery key once (you saved it in Step 1.2), then in Windows
  *Resume protection* so it re-seals against the new configuration.

## Windows partition won't mount in Ubuntu / "unclean state"

Fast Startup or hibernation left NTFS dirty. Boot Windows, disable Fast
Startup (`powercfg /h off`), shut down fully (hold Shift while clicking Shut
Down), then mount in Ubuntu. Never force-mount rw a hibernated NTFS volume.

## Clocks wrong after switching OSes

```bash
sudo timedatectl set-local-rtc 1 --adjust-system-clock
```

(Tells Linux to keep the hardware clock in local time like Windows does.)

## Elasticsearch container exits immediately

- `vm.max_map_count [65530] is too low` → the module sets this, but verify:
  `sysctl vm.max_map_count` should print `262144`
  (persisted in `/etc/sysctl.d/99-elastic.conf`).
- Check logs: `docker logs elasticsearch`. Memory-lock errors mean the
  `memlock` ulimits in the compose file were edited out — restore them.
- License says `trial` not `basic`: the compose file pins
  `xpack.license.self_generated.type=basic`; if you started the stack before
  with trial, run `docker compose down -v` (erases data) or POST
  `/_license/start_basic` to convert in place.

## Docker works with sudo only

Group membership hasn't landed in your session: `newgrp docker` for the
current shell, or log out/in. Verify with `id -nG | grep docker`.

## Ollama runs on CPU

`ollama ps` shows `100% CPU`? Check `nvidia-smi` works first (driver), then
`journalctl -u ollama | grep -i gpu`. Reinstalling after the driver
(`curl -fsSL https://ollama.com/install.sh | sh`) rebinds GPU support, then
`sudo systemctl restart ollama`.

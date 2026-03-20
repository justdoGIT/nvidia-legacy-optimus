# nvidia-legacy-optimus

> Bumblebee-based NVIDIA Optimus setup for **legacy GPUs** (390.xx / 470.xx) on modern Debian/Ubuntu kernels where official packages no longer exist.

[![Compatibility Reports](https://img.shields.io/badge/compatibility-see%20reports-blue)](COMPATIBILITY.md)
[![Driver](https://img.shields.io/badge/driver-390.157-green)](https://www.nvidia.com/en-us/drivers/unix/)
[![Tested On](https://img.shields.io/badge/kernel-6.1.x%20amd64-orange)]()

---

## Does This Work For My GPU?

**Check this before running anything.** Find your laptop model or GPU name below.

Don't know your GPU? Run:
```bash
lspci | grep -iE "3D|VGA|Display" | grep -i nvidia
```

| Laptop Model | GPU Name | Kernel | Distro | Status | Confidence |
|---|---|---|---|---|---|
| Lenovo G500 | GeForce GT 720M | 6.1.x | Debian 12 (Bookworm) | ✅ Working | ⭐⭐⭐ Confirmed |
| Lenovo G510 | GeForce GT 720M | 6.1.x | Debian 12 (Bookworm) | ✅ Working | ⭐ Reported |
| Lenovo G580 | GeForce GT 635M | 5.15.x | Ubuntu 22.04 | ⚠️ Partial | ⭐ Reported |

> **Confidence scale:**
> ⭐ Reported by one person on one machine
> ⭐⭐ Confirmed on 2–4 machines
> ⭐⭐⭐ Battle-tested across multiple users and kernel versions

**Don't see your hardware?** Check the full list → [COMPATIBILITY.md](COMPATIBILITY.md)
If yours works, please [submit a report](COMPATIBILITY.md#submitting-a-report) — it helps the next person.

---

## Why This Repo Exists

Debian Bookworm (12) dropped `nvidia-legacy-390xx` from the repos. The only install path is NVIDIA's `.run` installer — but it doesn't patch itself for kernels newer than ~5.x. The [inttf patcher](https://nvidia.if-not-true-then-false.com/) fixes that, but wiring GLX correctly for Bumblebee after a `.run` install is undocumented and non-trivial.

This repo documents everything learned the hard way.

---

## Architecture

```
Normal desktop session:
  Xorg → Intel modesetting (i915) → physical display

optirun / primusrun app:
  app → bumblebeed → headless Xorg:8 on NVIDIA
      → primus copies rendered frame → Intel display
```

**Key insight:** Bumblebee's headless Xorg needs NVIDIA's `libglx.so`, but the main Xorg needs Mesa's. They cannot share the same file. Solution: a private module path for Bumblebee at `/usr/lib/nvidia-bumblebee/extensions/`.

**Why Bumblebee and not PRIME offload?**
PRIME render offload (`__NV_PRIME_RENDER_OFFLOAD`) requires driver 435+.
The 390.xx driver predates that API. Bumblebee is the correct solution for this GPU generation.

---

## Prerequisites

```bash
# Kernel headers for current kernel
sudo apt install linux-headers-$(uname -r)

# Bumblebee stack
sudo apt install bumblebee primus primus-libs bbswitch-dkms

# Blacklist nouveau (must be done before driver install)
echo -e "blacklist nouveau\noptions nouveau modeset=0" | \
  sudo tee /etc/modprobe.d/blacklist-nvidia-nouveau.conf
sudo update-initramfs -u
```

---

## Installation

### Step 1 — Patch and build the driver

```bash
cd scripts/
bash inttf-nvidia-patcher.sh -v 390.157
```

This downloads the official `.run`, applies kernel compatibility patches, and repacks it.

### Step 2 — Install the patched driver

```bash
sudo bash NVIDIA-Linux-x86_64-390.157-patched-kernel-6.8.run \
  --no-nouveau-check \
  --dkms
```

`--dkms` registers the kernel module with DKMS so it auto-rebuilds on minor kernel updates.

### Step 3 — Deploy config files

```bash
# modprobe config
sudo cp configs/nvidia-drm-modeset.conf /etc/modprobe.d/

# Bumblebee configs
sudo cp configs/bumblebee.conf /etc/bumblebee/
sudo cp configs/xorg.conf.nvidia /etc/bumblebee/
sudo mkdir -p /etc/bumblebee/xorg.conf.d

# Private NVIDIA GLX path for bumblebee's headless Xorg
sudo mkdir -p /usr/lib/nvidia-bumblebee/extensions
sudo ln -sf /usr/lib/xorg/modules/extensions/libglx.so.390.157 \
            /usr/lib/nvidia-bumblebee/extensions/libglx.so

# Ensure main Xorg uses Mesa GLX (backup first)
[ -f /usr/lib/xorg/modules/extensions/libglx.so ] && \
  sudo cp /usr/lib/xorg/modules/extensions/libglx.so \
          /usr/lib/xorg/modules/extensions/libglx.so.mesa.bak
```

### Step 4 — GRUB + initramfs

```bash
# Add nvidia-drm.modeset=1 to kernel cmdline
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' \
  /etc/default/grub

sudo update-initramfs -u
sudo update-grub
```

### Step 5 — Add user to bumblebee group

```bash
sudo usermod -aG bumblebee $USER
# Log out and back in for group to take effect
```

### Step 6 — Reboot and verify

```bash
sudo reboot
# After login:
bash scripts/nvidia-health-check.sh
```

Expected output:
```
Intel GLX  → Mesa Intel(R) HD Graphics 4000
NVIDIA     → GeForce GT 720M/PCIe/SSE2
```

---

## Daily Usage

```bash
# Default — Intel (low power)
glxgears

# Offload to NVIDIA
optirun <app>
primusrun <app>        # faster, preferred for games

# Examples
primusrun steam
primusrun blender
primusrun glxgears

# Check NVIDIA is actually rendering
optirun nvidia-smi
```

---

## Recovery

See [`guides/nvidia-390xx-recovery-guide.md`](guides/nvidia-390xx-recovery-guide.md) for full recovery procedures covering:

- Kernel update broke the driver
- `apt upgrade` reset `libglx.so`
- Bumblebee daemon failures
- `modeset=N` after reboot
- Full nuclear reinstall

**Quick health check:**
```bash
bash scripts/nvidia-health-check.sh
```

---

## Repo Structure

```
nvidia-legacy-optimus/
├── README.md
├── COMPATIBILITY.md             # Hardware compatibility reports
├── configs/
│   ├── bumblebee.conf           # Bumblebee main config
│   ├── xorg.conf.nvidia         # Headless NVIDIA Xorg for bumblebee
│   └── nvidia-drm-modeset.conf  # Enables nvidia_drm KMS
├── guides/
│   └── nvidia-390xx-recovery-guide.md
└── scripts/
    ├── inttf-nvidia-patcher.sh  # Kernel-patches NVIDIA .run installer
    └── nvidia-health-check.sh   # Verifies full stack health
```

---

## Known Limitations

- **No Wayland support** — 390.xx has no Wayland EGL. XFCE/LightDM must run Xorg.
- **No PRIME render offload** — `__NV_PRIME_RENDER_OFFLOAD` requires driver 435+. Use `optirun`/`primusrun` instead.
- **bbswitch power gating** — Works on most Optimus laptops but not all ACPI implementations. If bbswitch fails, NVIDIA stays powered on (harmless, just uses more battery).
- **DKMS rebuilds** — Minor kernel updates trigger automatic DKMS rebuild. Major kernel jumps (5.x→6.x) may require re-running the patcher.

---

## References

- [inttf NVIDIA patcher](https://nvidia.if-not-true-then-false.com/patcher/)
- [Bumblebee Project](https://github.com/Bumblebee-Project/Bumblebee)
- [Debian Wiki — NVIDIA Optimus](https://wiki.debian.org/NVIDIA%20Optimus)
- [NVIDIA 390.xx release notes](https://www.nvidia.com/en-us/drivers/unix/)


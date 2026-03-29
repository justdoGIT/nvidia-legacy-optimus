# nvidia-legacy-optimus

> Bumblebee-based NVIDIA Optimus setup for legacy NVIDIA GPUs on Debian 12 (Bookworm).
> Tested and working on Lenovo G500 with GeForce GT 720M + Intel HD 4000.

[![Driver](https://img.shields.io/badge/driver-390.157-green)](https://www.nvidia.com/en-us/drivers/unix/)
[![Kernel](https://img.shields.io/badge/kernel-6.1.x%20amd64-orange)]()
[![Distro](https://img.shields.io/badge/distro-Debian%2012-red)]()

---

## Why This Repo Exists

Debian 12 dropped `nvidia-legacy-390xx` from its repos. Older Optimus laptops with GF117M/GK208
class GPUs still need the 390.xx legacy driver. The NVIDIA `.run` installer works after patching
but the resulting system layout is brittle — Bumblebee, GLVND, modprobe, and Xorg paths must all
agree precisely.

This repo captures the exact working layout from a live Debian 12 GT 720M system, including every
landmine hit and fixed during debugging.

---

## What You Get

```
Normal desktop work:
    Xorg → Intel i915 → NVIDIA OFF (bbswitch) → saves ~8W battery

GPU-intensive task (optirun / primusrun):
    app → bumblebeed → headless Xorg:8 on NVIDIA
        → primus copies rendered frame → Intel display
```

390.xx predates PRIME render offload. Bumblebee + primus is the correct model for this hardware.

---

## Hardware Compatibility

Check your GPU:

```bash
lspci | grep -iE "3D|VGA|Display" | grep -i nvidia
```

| Laptop | GPU | Kernel | Distro | Status |
|--------|-----|--------|--------|--------|
| Lenovo G500 | GeForce GT 720M (GF117M) | 6.1.x | Debian 12 | ✅ Confirmed |
| Lenovo G510 | GeForce GT 720M | 6.1.x | Debian 12 | ✅ Reported |
| Lenovo G580 | GeForce GT 635M | 5.15.x | Ubuntu 22.04 | ⚠️ Partial |

---

## Prerequisites

```bash
# Required kernel headers for DKMS modules
sudo apt install linux-headers-$(uname -r) build-essential dkms

# Bumblebee stack
sudo apt install bumblebee primus primus-libs

# bbswitch for GPU power management
sudo apt install bbswitch-dkms

# Mesa tools for verification
sudo apt install mesa-utils
```

---

## Installation — Step by Step

### Step 1 — Blacklist Nouveau

```bash
sudo tee /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

sudo update-initramfs -u
sudo reboot
```

Verify after reboot:
```bash
lsmod | grep nouveau   # must be empty
```

---

### Step 2 — Critical GRUB Parameter

> ⚠️ **DO NOT SKIP.** Without this, nvidia BAR0 = 0x0 and driver probe fails
> with "fallen off bus" on every load attempt. This was the root cause of all
> modprobe failures in testing.

```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&pci=realloc /' /etc/default/grub
sudo update-grub
```

Verify the line looks like:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet pci=realloc ..."
```

---

### Step 3 — Patch and Install the NVIDIA Driver

Stop the display manager first (must be done from a TTY):

```bash
sudo systemctl stop lightdm   # or gdm3 / sddm
```

Patch the installer for your kernel:

```bash
chmod +x scripts/inttf-nvidia-patcher.sh
bash scripts/inttf-nvidia-patcher.sh -v 390.157
```

Install with these exact flags:

```bash
sudo bash ./NVIDIA-Linux-x86_64-390.157-patched.run \
    --dkms \
    --no-opengl-files \
    --no-nouveau-check \
    --no-x-check
```

> `--no-opengl-files` is deliberate. It prevents the installer from overwriting Mesa-managed
> GL libraries. Mesa must stay in control of the system libGL/libEGL stack.

Verify the DKMS module built correctly:

```bash
sudo dkms status | grep nvidia
# → nvidia/390.157, 6.1.x-amd64, x86_64: installed
```

---

### Step 4 — Copy the libglx Isolation File

This is the file that gives bumblebee's headless Xorg its own private NVIDIA GLX without
conflicting with the system Mesa libglx used by Intel.

Extract from the installer and copy:

```bash
./NVIDIA-Linux-x86_64-390.157-patched.run --extract-only
cd NVIDIA-Linux-x86_64-390.157-patched

sudo mkdir -p /usr/lib/x86_64-linux-gnu/nvidia/xorg
sudo cp libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/
sudo ln -sf libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
```

Verify:

```bash
ls -la /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
# → libglx.so -> libglx.so.390.157
```

> Without this, bumblebee's Xorg either cannot find GLX or loads the wrong Mesa one,
> causing optirun to fail silently.

---

### Step 5 — Deploy Configuration Files

```bash
# modprobe configs
sudo cp configs/gpu-optimus.conf      /etc/modprobe.d/
sudo cp configs/nvidia-force-id.conf  /etc/modprobe.d/
sudo cp configs/bbswitch.conf         /etc/modprobe.d/

# Bumblebee config
sudo cp configs/bumblebee.conf        /etc/bumblebee/
sudo mkdir -p /etc/bumblebee/xorg.conf.d
sudo cp configs/xorg.nvidia.conf      /etc/bumblebee/xorg.conf.d/xorg.conf.nvidia

# Intel primary Xorg config — keeps Mesa GLX isolated from NVIDIA
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-modesetting.conf << 'EOF'
Section "Device"
    Identifier  "Intel"
    Driver      "modesetting"
    BusID       "PCI:0:2:0"
    Option      "DRI" "3"
EndSection

Section "ServerFlags"
    Option "ModulePath" "/usr/lib/xorg/modules"
EndSection
EOF
```

---

### Step 6 — Install the Boot Service

This service loads bbswitch and powers the GPU off at boot before bumblebee starts:

```bash
sudo cp configs/nvidia-acpi-on.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nvidia-acpi-on.service
```

---

### Step 7 — Add Yourself to the bumblebee Group

```bash
sudo usermod -aG bumblebee $USER
```

Log out and back in, or run `newgrp bumblebee` for immediate effect.

---

### Step 8 — If You Previously Used envycontrol

> ⚠️ envycontrol leaves behind landmines that silently break everything.

```bash
# Remove the udev rule that actively removes the GPU from the PCI bus
sudo rm -f /etc/udev/rules.d/50-remove-nvidia.rules
sudo udevadm control --reload-rules

# Remove envycontrol's modprobe blacklist (we replace it with our own)
sudo rm -f /etc/modprobe.d/blacklist-nvidia.conf

# Remove envycontrol itself
sudo pip3 uninstall envycontrol 2>/dev/null || sudo rm -f /usr/local/bin/envycontrol
```

---

### Step 9 — Rebuild initramfs and Reboot

```bash
sudo update-initramfs -u
sudo reboot
```

---

## Verification After Reboot

Run in order:

```bash
# 1. GPU must be visible on PCI bus
lspci | grep -i nvidia
# → 01:00.0 3D controller: NVIDIA Corporation GF117M ...

# 2. BARs must be non-zero (pci=realloc working)
sudo cat /sys/bus/pci/devices/0000:01:00.0/resource | head -1
# → 0x00000000d2000000 ... (NOT all zeros)

# 3. bbswitch must have powered GPU off at boot
cat /proc/acpi/bbswitch
# → 0000:01:00.0 OFF

# 4. bumblebee must be running
sudo systemctl status bumblebeed --no-pager
# → Active: active (running)

# 5. Intel GLX must work (primary display)
glxinfo | grep renderer
# → OpenGL renderer string: Mesa Intel(R) HD Graphics 4000

# 6. NVIDIA on demand must work
optirun glxinfo | grep renderer
# → OpenGL renderer string: GeForce GT 720M/PCIe/SSE2
```

---

## Daily Usage

```bash
# Normal desktop — Intel renders, NVIDIA stays off
glxinfo | grep renderer

# Launch any app on NVIDIA GPU
optirun <application>
primusrun <application>

# Quick wrapper script (included in repo)
gpu-run <application>

# Check GPU power state
cat /proc/acpi/bbswitch    # OFF = idle, ON = active

# Check NVIDIA status while running
optirun nvidia-smi

# Benchmark
optirun glmark2
```

---

## Config File Reference

### `/etc/modprobe.d/gpu-optimus.conf`

```
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_InitializeSystemMemoryAllocations=0
```

### `/etc/modprobe.d/nvidia-force-id.conf`

```
alias pci:v000010DEd00001140sv*sd*bc03sc*i* nvidia
options nvidia NVreg_Mobile=1
```

> `NVreg_Mobile=1` is critical — it tells the driver this is an Optimus laptop,
> not a discrete desktop GPU. Without it, the driver makes wrong assumptions about
> display connectivity.
> The alias forces nvidia to bind to PCI ID `10de:1140` (GF117M) at boot.

### `/etc/modprobe.d/bbswitch.conf`

```
options bbswitch load_state=1 unload_state=1 skip_optimus_dsm=0
```

> `load_state=1` ensures GPU is ON when bbswitch loads so it can attach.
> `skip_optimus_dsm=0` enables DSM-based power control (required for this GPU).

### `/etc/bumblebee/bumblebee.conf` (key fields)

```ini
Driver=nvidia
Bridge=primus
[driver-nvidia]
KernelDriver=nvidia
PMMethod=bbswitch
LibraryPath=/usr/lib/x86_64-linux-gnu/nvidia:/usr/lib/x86_64-linux-gnu
XorgModulePath=/usr/lib/x86_64-linux-gnu/nvidia/xorg,/usr/lib/xorg/modules/drivers,/usr/lib/xorg/modules
XorgConfFile=/etc/bumblebee/xorg.conf.d/xorg.conf.nvidia
AlwaysUnloadKernelDriver=false
```

> `XorgModulePath` must list the private nvidia/xorg path first so bumblebee's Xorg
> finds `libglx.so.390.157` instead of Mesa's libglx.

### `/etc/bumblebee/xorg.conf.d/xorg.conf.nvidia` (key fields)

```
Section "Device"
    Driver      "nvidia"
    BusID       "PCI:1:0:0"
    Option      "NoLogo"          "true"
    Option      "UseDisplayDevice" "none"
EndSection
```

> Replace `BusID` if your NVIDIA GPU is at a different PCIe address.
> Check with: `lspci | grep -i nvidia` then convert `01:00.0` → `PCI:1:0:0`

---

## How It Works — The Layered Architecture

```
Boot
  ↓
pci=realloc → kernel assigns prefetchable BARs to GPU correctly
  ↓
nvidia-force-id.conf → nvidia.ko auto-binds to 10de:1140 at PCI enumeration
  ↓
nvidia-acpi-on.service → loads bbswitch → sets GPU OFF
  ↓
bumblebeed starts → waits for optirun requests

Runtime (optirun app)
  ↓
bumblebeed receives request
  ↓
bbswitch: echo ON → /proc/acpi/bbswitch (ACPI _DSM call internally)
  ↓
bumblebee starts headless Xorg:8
  ↓
Xorg:8 loads nvidia_drv.so from /usr/lib/xorg/modules/drivers/
Xorg:8 loads libglx.so from /usr/lib/x86_64-linux-gnu/nvidia/xorg/
  ↓
primus renders app on NVIDIA, copies frames to Intel framebuffer
  ↓
app exits → bumblebee kills Xorg:8 → bbswitch: echo OFF → GPU powers down
```

---

## Known Limitations

- No Wayland support. 390.xx predates GBM-based nvidia Wayland.
- No PRIME render offload (`DRI_PRIME=1`). That API requires driver ≥ 455.
- Only `optirun` / `primusrun` model works for on-demand NVIDIA.
- Kernel updates require rerunning the patcher and reinstalling the driver.
- BAR 6 (ROM) fails to assign — harmless, does not affect rendering.

---

## Troubleshooting

### `optirun: Could not load GPU driver`

```bash
# Check if bbswitch turned GPU on
cat /proc/acpi/bbswitch

# Check if nvidia module is loaded
lsmod | grep nvidia

# Check bumblebee journal
sudo journalctl -u bumblebeed -n 30 --no-pager
```

### `nvidia: probe of 0000:01:00.0 failed with error -1 / BAR0 is 0M`

```bash
# pci=realloc is missing from GRUB
grep CMDLINE /etc/default/grub
# Must contain: pci=realloc
```

### `GPU not visible after reboot` / `lspci shows nothing`

```bash
# Check for envycontrol's udev remove rule
ls /etc/udev/rules.d/50-remove-nvidia.rules
# If exists: sudo rm /etc/udev/rules.d/50-remove-nvidia.rules
```

### `bbswitch: No discrete VGA device found`

```bash
# Check GPU PCI class
lspci -n | grep "01:00"
# GF117M shows as 0302 (3D controller), not 0300 (VGA)
# Fix: ensure bbswitch.conf has skip_optimus_dsm=0
```

### `glxinfo: GLX missing on display`

```bash
# Check main Xorg ModulePath — must NOT include nvidia/xorg
grep ModulePath /var/log/Xorg.0.log
# Should show only: /usr/lib/xorg/modules

# Check 10-modesetting.conf is in place
cat /etc/X11/xorg.conf.d/10-modesetting.conf
```

### `lightdm fails to start`

```bash
# Check for VirtualGL hooks in lightdm config
grep -r "vgl" /etc/lightdm/
# If found: sudo sed -i '/vglgenkey/d' /etc/lightdm/lightdm.conf.d/*
```

---

## Repo Structure

```
nvidia-legacy-optimus/
├── README.md
├── COMPATIBILITY.md
├── configs/
│   ├── bumblebee.conf
│   ├── gpu-optimus.conf
│   ├── nvidia-force-id.conf
│   ├── bbswitch.conf
│   ├── xorg.nvidia.conf
│   └── nvidia-acpi-on.service
├── guides/
│   └── nvidia-390.157-g500-recovery-guide.md
└── scripts/
    ├── gpu-run
    ├── inttf-nvidia-patcher.sh
    └── nvidia-health-check.sh
```

---

## Quick Health Check

```bash
bash scripts/nvidia-health-check.sh
```

Or manually:

```bash
echo "=== PCI ===" && lspci | grep -i nvidia
echo "=== BARs ===" && sudo cat /sys/bus/pci/devices/0000:01:00.0/resource | head -1
echo "=== bbswitch ===" && cat /proc/acpi/bbswitch
echo "=== bumblebee ===" && systemctl is-active bumblebeed
echo "=== Intel GLX ===" && glxinfo 2>/dev/null | grep "OpenGL renderer"
echo "=== NVIDIA GLX ===" && optirun glxinfo 2>/dev/null | grep "OpenGL renderer"
```

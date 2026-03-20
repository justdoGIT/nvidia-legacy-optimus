# NVIDIA 390.xx Driver Recovery Guide
## Lenovo G500 — Debian Bookworm — Bumblebee/PRIME Setup

> **System:** Lenovo G500 | Intel HD 4000 (i915) + NVIDIA GeForce GT 720M (GF117)
> **Driver:** 390.157 via `inttf-nvidia-patcher.sh` (.run installer)
> **Kernel:** 6.1.x amd64 | **Desktop:** XFCE + LightDM

---

## Architecture Overview

```
Normal desktop:
  Xorg → Intel modesetting (card0) → LVDS-1 display

GPU-accelerated app (optirun/primusrun):
  app → bumblebeed → headless Xorg:8 → NVIDIA (card1) → primus frame copy → Intel display
```

**Why Bumblebee and not PRIME offload?**
PRIME render offload (`__NV_PRIME_RENDER_OFFLOAD`) requires driver 435+.
The 390.xx driver predates that API. Bumblebee is the correct solution for this GPU generation.

---

## Critical File Map

| File | Purpose |
|------|---------|
| `/usr/lib/xorg/modules/extensions/libglx.so` | Symlink → Mesa GLX (main Xorg) |
| `/usr/lib/xorg/modules/extensions/libglx.so.390.157` | NVIDIA GLX module |
| `/usr/lib/xorg/modules/extensions/libglx.so.mesa.bak` | Mesa GLX backup |
| `/usr/lib/nvidia-bumblebee/extensions/libglx.so` | Symlink → NVIDIA GLX (bumblebee Xorg) |
| `/etc/bumblebee/bumblebee.conf` | Bumblebee main config |
| `/etc/bumblebee/xorg.conf.nvidia` | Headless NVIDIA Xorg config |
| `/etc/modprobe.d/nvidia-drm-modeset.conf` | Enables nvidia_drm modesetting |
| `~/scripts/inttf-nvidia-patcher.sh` | Kernel-patches and repacks .run driver |

---

## Scenario 1: Kernel Update Broke the Driver

### Symptoms
- `nvidia-smi` fails: `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`
- `lsmod | grep nvidia` returns nothing
- `optirun glxinfo` fails

### Cause
The NVIDIA kernel module (`nvidia.ko`) is built against a specific kernel version.
A new kernel means the old `.ko` is incompatible — needs a rebuild via the `.run` installer.

### Fix

```bash
# 1. Confirm which kernel is running
uname -r

# 2. Install headers for new kernel
sudo apt install linux-headers-$(uname -r)

# 3. Re-run the patcher for 390.157
cd ~/scripts
bash inttf-nvidia-patcher.sh -v 390.157

# 4. Install the patched .run (suppress old module check)
cd NVIDIA-Linux-x86_64-390.157-patched-kernel-6.8.run  # adjust filename
sudo bash NVIDIA-Linux-x86_64-390.157-patched-kernel-6.8.run \
  --no-nouveau-check \
  --no-kernel-module-source \
  --dkms

# 5. After install — restore libglx symlinks (installer may reset them)
sudo ln -sf /usr/lib/xorg/modules/extensions/libglx.so.mesa.bak \
            /usr/lib/xorg/modules/extensions/libglx.so

sudo mkdir -p /usr/lib/nvidia-bumblebee/extensions
sudo ln -sf /usr/lib/xorg/modules/extensions/libglx.so.390.157 \
            /usr/lib/nvidia-bumblebee/extensions/libglx.so

# 6. Rebuild initramfs to bake modprobe config
sudo update-initramfs -u

# 7. Restart bumblebee
sudo systemctl restart bumblebeed

# 8. Test
optirun glxinfo | grep renderer
# Expected: OpenGL renderer string: GeForce GT 720M/PCIe/SSE2
```

---

## Scenario 2: `xserver-xorg-core` Update Reset libglx.so

### Symptoms
- Desktop GLX broken: `glxinfo` → `GLX missing on display :0`
- OR optirun fails: `Failed to initialize GLX module`

### Cause
`apt upgrade` updated `xserver-xorg-core` and overwrote `/usr/lib/xorg/modules/extensions/libglx.so`
back to Mesa's version. Bumblebee's private NVIDIA GLX path is unaffected.

### Fix

```bash
# Check what libglx.so currently points to
ls -la /usr/lib/xorg/modules/extensions/libglx.so
strings /usr/lib/xorg/modules/extensions/libglx.so | grep -iE "nvidia|mesa" | head -3

# If it's Mesa AND you need NVIDIA GLX for main Xorg (not needed in Bumblebee setup):
# The Bumblebee setup uses Mesa for main Xorg — so if libglx.so is Mesa, that's CORRECT.

# If libglx.so.mesa.bak is missing (overwrite happened):
sudo cp /usr/lib/xorg/modules/extensions/libglx.so \
        /usr/lib/xorg/modules/extensions/libglx.so.mesa.bak

# Verify bumblebee's private path is intact
ls -la /usr/lib/nvidia-bumblebee/extensions/libglx.so
# Must point to: /usr/lib/xorg/modules/extensions/libglx.so.390.157

# If broken, recreate it:
sudo mkdir -p /usr/lib/nvidia-bumblebee/extensions
sudo ln -sf /usr/lib/xorg/modules/extensions/libglx.so.390.157 \
            /usr/lib/nvidia-bumblebee/extensions/libglx.so

sudo systemctl restart bumblebeed
optirun glxinfo | grep renderer
```

---

## Scenario 3: Bumblebee Daemon Fails to Start

### Symptoms
- `optirun` → `Could not connect to bumblebee daemon`
- `systemctl status bumblebeed` → failed/dead

### Diagnosis

```bash
sudo journalctl -u bumblebeed -n 30 --no-pager
ls /var/log/Xorg.8.log && grep -iE "error|fail" /var/log/Xorg.8.log
```

### Common causes and fixes

**A) bbswitch module not found**
```
[ERROR]Module 'bbswitch' not found.
```
```bash
# Rebuild bbswitch DKMS for current kernel
sudo dkms install bbswitch/0.8 -k $(uname -r)
# Or reinstall
sudo apt install --reinstall bbswitch-dkms
```

**B) nvidia module ref count prevents unload (harmless)**
```
[ERROR]Failed to unload module 'nvidia' (ref count: X)
```
This is informational — bumblebee still works. nvidia.ko is held by the running X session.
No action needed.

**C) GLX module mismatch in headless Xorg**
```
[EE] NVIDIA(0): Failed to initialize the GLX module
```
```bash
# Verify private NVIDIA GLX path
ls -la /usr/lib/nvidia-bumblebee/extensions/libglx.so
# Must be: -> /usr/lib/xorg/modules/extensions/libglx.so.390.157

# Verify bumblebee.conf XorgModulePath
grep XorgModulePath /etc/bumblebee/bumblebee.conf
# Must be: XorgModulePath=/usr/lib/nvidia-bumblebee,/usr/lib/xorg/modules/drivers,/usr/lib/xorg/modules

sudo systemctl restart bumblebeed
```

**D) Missing xorg.conf.d directory**
```
[ERROR] Unable to locate/open config directory: "/etc/bumblebee/xorg.conf.d"
```
```bash
sudo mkdir -p /etc/bumblebee/xorg.conf.d
sudo systemctl restart bumblebeed
```

---

## Scenario 4: modeset=N After Reboot

### Symptoms
- `cat /sys/module/nvidia_drm/parameters/modeset` → `N`
- Only 1 xrandr provider

### Fix

```bash
# Check modprobe config exists
cat /etc/modprobe.d/nvidia-drm-modeset.conf
# Must contain: options nvidia-drm modeset=1

# If missing, recreate it
echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf

# Check GRUB cmdline (watch for typos: modset vs modeset)
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
# Must contain: nvidia-drm.modeset=1  (NOT nvidia-drm.modset=1)

# Fix typo if present
sudo sed -i 's/nvidia-drm\.modset=/nvidia-drm.modeset=/' /etc/default/grub

# Rebuild initramfs + grub
sudo update-initramfs -u && sudo update-grub
sudo reboot
```

---

## Scenario 5: Full Reinstall (Nuclear Option)

Use this when nothing else works — fresh driver install from scratch.

```bash
# Step 1: Remove old driver cleanly
sudo /usr/bin/nvidia-uninstall

# Step 2: Ensure nouveau stays blacklisted
cat /etc/modprobe.d/blacklist-nvidia-nouveau.conf
# Should contain:
#   blacklist nouveau
#   options nouveau modeset=0
# If missing:
echo -e "blacklist nouveau\noptions nouveau modeset=0" | \
  sudo tee /etc/modprobe.d/blacklist-nvidia-nouveau.conf

# Step 3: Install kernel headers
sudo apt install linux-headers-$(uname -r)

# Step 4: Run patcher and install
cd ~/scripts
bash inttf-nvidia-patcher.sh -v 390.157
cd NVIDIA-Linux-x86_64-390.157-patched-kernel-6.8.run  # adjust
sudo bash NVIDIA-Linux-x86_64-390.157-patched-kernel-6.8.run \
  --no-nouveau-check --dkms

# Step 5: Restore all config files (see Config Files Reference below)

# Step 6: Rebuild initramfs + grub + reboot
sudo update-initramfs -u && sudo update-grub && sudo reboot

# Step 7: Verify
optirun glxinfo | grep renderer
```

---

## Config Files Reference

### `/etc/modprobe.d/nvidia-drm-modeset.conf`
```
options nvidia-drm modeset=1
```

### `/etc/bumblebee/bumblebee.conf`
```ini
[bumblebeed]
VirtualDisplay=:8
KeepUnusedXServer=false
ServerGroup=bumblebee
TurnCardOffAtExit=false
NoEcoModeOverride=false
Driver=nvidia
XorgConfFile=/etc/bumblebee/xorg.conf.nvidia

[optirun]
Bridge=primus
VGLTransport=proxy
PrimusLibraryPath=/usr/lib/x86_64-linux-gnu/primus:/usr/lib/i386-linux-gnu/primus
AllowFallbackToIGC=false

[driver-nvidia]
KernelDriver=nvidia
PMMethod=bbswitch
LibraryPath=/usr/lib/x86_64-linux-gnu:/usr/lib/i386-linux-gnu
XorgModulePath=/usr/lib/nvidia-bumblebee,/usr/lib/xorg/modules/drivers,/usr/lib/xorg/modules
XorgConfFile=/etc/bumblebee/xorg.conf.nvidia

[driver-nouveau]
KernelDriver=nouveau
PMMethod=auto
XorgConfFile=/etc/bumblebee/xorg.conf.nouveau
```

### `/etc/bumblebee/xorg.conf.nvidia`
```
Section "ServerLayout"
    Identifier  "Layout0"
    Option      "AutoAddDevices" "false"
    Option      "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier  "DiscreteNvidia"
    Driver      "nvidia"
    VendorName  "NVIDIA Corporation"
    BusID       "PCI:1:0:0"
    Option      "ProbeAllGpus" "false"
    Option      "NoLogo" "true"
    Option      "UseEDID" "false"
    Option      "UseDisplayDevice" "none"
EndSection
```

### GRUB cmdline (in `/etc/default/grub`)
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet modprobe.blacklist=nouveau rd.driver.blacklist=nouveau nouveau.modeset=0 nvidia-drm.modeset=1"
```

---

## Full Health Check Script

Save as `~/scripts/nvidia-health-check.sh` and run after any system update:

```bash
#!/bin/bash

echo "=== nvidia-smi ===" && nvidia-smi | head -9
echo ""
echo "=== Kernel modules ==="
lsmod | grep -E "nvidia|bbswitch"
echo ""
echo "=== modeset ===" && cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "N/A (Bumblebee mode - not needed)"
echo ""
echo "=== libglx symlinks ==="
ls -la /usr/lib/xorg/modules/extensions/libglx.so
ls -la /usr/lib/nvidia-bumblebee/extensions/libglx.so 2>/dev/null || echo "MISSING: bumblebee GLX path"
echo ""
echo "=== bumblebeed status ==="
systemctl is-active bumblebeed
echo ""
echo "=== Intel GLX ===" && glxinfo 2>/dev/null | grep renderer || echo "FAIL"
echo ""
echo "=== NVIDIA via optirun ==="
optirun glxinfo 2>/dev/null | grep renderer || echo "FAIL"
```

```bash
chmod +x ~/scripts/nvidia-health-check.sh
```

---

## Post-Update Checklist

Run this after every `apt upgrade` or kernel update:

```bash
bash ~/scripts/nvidia-health-check.sh
```

If anything fails, work through Scenarios 1–4 above in order:

1. `nvidia-smi` fails → **Scenario 1** (rebuild kernel module)
2. `libglx.so` wrong → **Scenario 2** (restore symlinks)
3. `bumblebeed` dead → **Scenario 3** (daemon fix)
4. `modeset=N` → **Scenario 4** (GRUB/initramfs fix)
5. Everything broken → **Scenario 5** (full reinstall)

---

## Daily Usage

```bash
# Run app on Intel (default, low power)
glxgears

# Run app on NVIDIA (games, compute, GPU-heavy)
optirun <app>
primusrun <app>       # faster — use this for games

# Examples
primusrun glxgears
primusrun steam
primusrun blender

# Verify which GPU is rendering
optirun nvidia-smi    # shows active NVIDIA processes
glxinfo | grep renderer          # should say: Mesa Intel HD Graphics 4000
optirun glxinfo | grep renderer  # should say: GeForce GT 720M
```

---

*Guide built from live debugging session — March 2026*
*Driver: NVIDIA 390.157 | Kernel: 6.1.0-44-amd64 | Debian Bookworm*


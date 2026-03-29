# NVIDIA 390.157 Recovery Guide
## Lenovo G500 / G510 / Similar Optimus Laptops

> **System:** Intel HD 4000 + GeForce GT 720M (GF117M / PCI 10de:1140)
> **Driver:** 390.157 via `scripts/inttf-nvidia-patcher.sh`
> **Kernel:** 6.1.x amd64
> **Display stack:** Xorg + Bumblebee + Primus + bbswitch
> **Verified against live system:** March 29, 2026

---

## Quick Health Check

Run this first before any scenario:

```bash
bash scripts/nvidia-health-check.sh
```

Or manually:

```bash
echo "=== GPU on bus ===" && lspci | grep -i nvidia
echo "=== BAR0 assigned ===" && sudo cat /sys/bus/pci/devices/0000:01:00.0/resource | head -1
echo "=== bbswitch ===" && cat /proc/acpi/bbswitch
echo "=== bumblebee ===" && systemctl is-active bumblebeed
echo "=== Intel GLX ===" && glxinfo 2>/dev/null | grep "OpenGL renderer"
echo "=== NVIDIA GLX ===" && optirun glxinfo 2>/dev/null | grep "OpenGL renderer"
```

Expected results:

```
GPU on bus      → 01:00.0 3D controller: NVIDIA ... GF117M
BAR0 assigned   → 0x00000000d2000000 ... (NOT all zeros)
bbswitch        → 0000:01:00.0 OFF
bumblebee       → active
Intel GLX       → Mesa Intel(R) HD Graphics 4000
NVIDIA GLX      → GeForce GT 720M/PCIe/SSE2
```

---

## Live Working Layout

These are the required files on the reference machine:

| Path | Purpose |
|------|---------|
| `/usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so` | Symlink → libglx.so.390.157 |
| `/usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so.390.157` | NVIDIA GLX used by Bumblebee Xorg |
| `/etc/bumblebee/bumblebee.conf` | Main Bumblebee config |
| `/etc/bumblebee/xorg.conf.d/xorg.conf.nvidia` | Headless NVIDIA Xorg config |
| `/etc/modprobe.d/gpu-optimus.conf` | Nouveau blacklist + nvidia options |
| `/etc/modprobe.d/nvidia-force-id.conf` | Binds nvidia.ko to 10de:1140 at boot |
| `/etc/modprobe.d/bbswitch.conf` | bbswitch load parameters |
| `/etc/X11/xorg.conf.d/10-modesetting.conf` | Intel primary Xorg, Mesa-only ModulePath |
| `/etc/systemd/system/nvidia-acpi-on.service` | Loads bbswitch, sets GPU off at boot |
| GRUB: `pci=realloc` | Fixes PCIe BAR assignment — mandatory |

---

## Mandatory Permanent Settings (check these first in any scenario)

### GRUB

```bash
grep CMDLINE /etc/default/grub
# Must contain: pci=realloc
```

If missing:
```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&pci=realloc /' /etc/default/grub
sudo update-grub
```

> Without `pci=realloc`, nvidia BAR0 = 0x0 and driver probe fails on every boot
> with "fallen off bus". This is the single most common failure mode.

### Intel Xorg config

```bash
cat /etc/X11/xorg.conf.d/10-modesetting.conf
```

Must contain `ModulePath "/usr/lib/xorg/modules"` (no nvidia path). If missing:

```bash
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

### bbswitch parameters

```bash
cat /etc/modprobe.d/bbswitch.conf
# Must contain: options bbswitch load_state=1 unload_state=1 skip_optimus_dsm=0
```

If missing or wrong:
```bash
sudo tee /etc/modprobe.d/bbswitch.conf << 'EOF'
options bbswitch load_state=1 unload_state=1 skip_optimus_dsm=0
EOF
```

### libglx symlink

```bash
ls -la /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
# Must be: libglx.so -> libglx.so.390.157
```

---

## Scenario 1: Kernel Update Broke NVIDIA

**Symptoms:**
- `optirun` fails after `apt upgrade`
- `dkms status` shows nvidia module missing for new kernel
- `lsmod | grep nvidia` empty

**Fix:**

```bash
sudo apt install linux-headers-$(uname -r)
bash scripts/inttf-nvidia-patcher.sh -v 390.157

sudo systemctl stop lightdm
sudo bash ./NVIDIA-Linux-x86_64-390.157-patched.run \
    --dkms \
    --no-opengl-files \
    --no-nouveau-check \
    --no-x-check

# Verify module rebuilt
sudo dkms status | grep nvidia
# → nvidia/390.157, $(uname -r), x86_64: installed

sudo update-initramfs -u
sudo reboot
```

If GL still fails after reboot, check the libglx symlink (Scenario 2).

---

## Scenario 2: Runtime Files Drifted / libglx Missing

**Symptoms:**
- `optirun glxinfo` fails with "Could not load GPU driver"
- `/var/log/Xorg.8.log` shows GLX errors
- `ls /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so` → missing or broken

**Fix:**

```bash
# Extract installer
./NVIDIA-Linux-x86_64-390.157-patched.run --extract-only
cd NVIDIA-Linux-x86_64-390.157-patched

# Restore libglx — note: NOT in extensions/ subdirectory
sudo mkdir -p /usr/lib/x86_64-linux-gnu/nvidia/xorg
sudo cp libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/
sudo ln -sf libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so

# Restore TLS library
sudo cp tls/libnvidia-tls.so.390.157 /usr/lib/x86_64-linux-gnu/

sudo ldconfig

# Verify bumblebee XorgModulePath still correct
grep XorgModulePath /etc/bumblebee/bumblebee.conf
# → XorgModulePath=/usr/lib/x86_64-linux-gnu/nvidia/xorg,/usr/lib/xorg/modules/...

sudo systemctl restart bumblebeed
optirun glxinfo | grep renderer
```

---

## Scenario 3: Bumblebee Daemon Fails to Start

**Symptoms:**
- `systemctl status bumblebeed` → failed
- `journalctl -u bumblebeed` shows "No discrete video card found"

**Diagnosis:**

```bash
# Is GPU on PCI bus?
lspci | grep -i nvidia

# Is bbswitch loaded?
cat /proc/acpi/bbswitch

# Full bumblebee log
sudo journalctl -u bumblebeed -n 50 --no-pager
```

**Fix A — GPU not on PCI bus:**

```bash
# GPU stuck in D3cold after bad shutdown
# pci=realloc in GRUB + cold reboot usually fixes this
sudo shutdown -h now
# Wait 15 seconds, then power on (not just reboot)
```

**Fix B — bbswitch missing:**

```bash
sudo apt install --reinstall bbswitch-dkms
sudo dkms install bbswitch/0.8 -k $(uname -r)
sudo modprobe bbswitch load_state=1 unload_state=1 skip_optimus_dsm=0
cat /proc/acpi/bbswitch
```

**Fix C — nvidia-acpi-on service missing:**

```bash
sudo cp configs/nvidia-acpi-on.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-acpi-on.service
```

---

## Scenario 4: Intel GLX Broken (GLX extension missing)

**Symptoms:**
- `glxinfo` shows "GLX extension missing"
- `Xlib: extension GLX missing on display :0`
- Desktop renders slowly or fails

**Cause:** NVIDIA's libglx loaded by main Xorg instead of Mesa's.

**Diagnosis:**

```bash
grep -i "glx\|modulepath" /var/log/Xorg.0.log | head -10
# Bad: ModulePath includes /usr/lib/x86_64-linux-gnu/nvidia/xorg
# Bad: Loading /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
# Bad: (EE) Failed to initialize GLX extension
```

**Fix:**

```bash
# Ensure 10-modesetting.conf exists with correct ModulePath
cat /etc/X11/xorg.conf.d/10-modesetting.conf

# Ensure nvidia-drm module is not loaded (it triggers OutputClass)
lsmod | grep nvidia_drm

# If nvidia_drm is loaded and causing issues, check blacklist
cat /etc/modprobe.d/gpu-optimus.conf
# Must NOT blacklist nvidia (only nouveau)
# nvidia itself is needed — only nvidia_drm modeset should be set

sudo systemctl restart lightdm
```

---

## Scenario 5: Recovering from envycontrol

**Symptoms:**
- Previously used `envycontrol -s integrated` or similar
- GPU invisible: `lspci | grep nvidia` returns nothing
- bbswitch fails: "No such device"

**envycontrol leaves these landmines:**

```bash
# Check for each:
ls /etc/udev/rules.d/50-remove-nvidia.rules    # removes GPU from PCI bus
ls /etc/modprobe.d/blacklist-nvidia.conf        # blacklists all nvidia modules
```

**Fix:**

```bash
# Remove the GPU-removing udev rule
sudo rm -f /etc/udev/rules.d/50-remove-nvidia.rules
sudo udevadm control --reload-rules

# Remove nvidia blacklist
sudo rm -f /etc/modprobe.d/blacklist-nvidia.conf

# Remove envycontrol
sudo pip3 uninstall envycontrol 2>/dev/null || sudo rm -f /usr/local/bin/envycontrol

# Restore our modprobe config
sudo cp configs/gpu-optimus.conf /etc/modprobe.d/
sudo cp configs/nvidia-force-id.conf /etc/modprobe.d/
sudo cp configs/bbswitch.conf /etc/modprobe.d/

sudo update-initramfs -u

# Cold reboot required — warm reboot may not bring GPU back
sudo shutdown -h now
```

---

## Scenario 6: Full Reinstall from Scratch

```bash
# 1. Uninstall existing driver
sudo /usr/bin/nvidia-uninstall 2>/dev/null || true

# 2. Remove all leftover configs
sudo rm -f /etc/modprobe.d/blacklist-nvidia.conf
sudo rm -f /etc/udev/rules.d/50-remove-nvidia.rules
sudo rm -f /etc/X11/xorg.conf

# 3. Blacklist nouveau
sudo tee /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

# 4. GRUB — add pci=realloc (mandatory)
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&pci=realloc /' /etc/default/grub
sudo update-grub

# 5. Rebuild initramfs and reboot to TTY
sudo update-initramfs -u
sudo reboot   # boot to TTY, do not start display manager

# 6. Patch and install driver
bash scripts/inttf-nvidia-patcher.sh -v 390.157
sudo systemctl stop lightdm
sudo bash ./NVIDIA-Linux-x86_64-390.157-patched.run \
    --dkms \
    --no-opengl-files \
    --no-nouveau-check \
    --no-x-check

# 7. Restore libglx
./NVIDIA-Linux-x86_64-390.157-patched.run --extract-only
cd NVIDIA-Linux-x86_64-390.157-patched
sudo mkdir -p /usr/lib/x86_64-linux-gnu/nvidia/xorg
sudo cp libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/
sudo ln -sf libglx.so.390.157 /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
sudo cp tls/libnvidia-tls.so.390.157 /usr/lib/x86_64-linux-gnu/
sudo ldconfig
cd ..

# 8. Deploy all configs
sudo cp configs/gpu-optimus.conf       /etc/modprobe.d/
sudo cp configs/nvidia-force-id.conf   /etc/modprobe.d/
sudo cp configs/bbswitch.conf          /etc/modprobe.d/
sudo cp configs/bumblebee.conf         /etc/bumblebee/
sudo mkdir -p /etc/bumblebee/xorg.conf.d
sudo cp configs/xorg.nvidia.conf       /etc/bumblebee/xorg.conf.d/xorg.conf.nvidia

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

sudo cp configs/nvidia-acpi-on.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nvidia-acpi-on.service

sudo usermod -aG bumblebee $USER

# 9. Final rebuild and cold boot
sudo update-initramfs -u
sudo shutdown -h now   # cold shutdown, not reboot
```

---

## Notes

- `--no-opengl-files` is always intentional. Mesa owns the system GL stack.
- `nvidia-force-id.conf` is device-specific for PCI ID `10de:1140` (GF117M/GT 720M).
  Check your GPU ID: `lspci -n | grep "01:00"` and update the alias if different.
- Cold shutdown (power off + power on) is more reliable than warm reboot
  when recovering from D3cold GPU power states.
- acpi_call module is NOT required for normal operation.
  bbswitch uses the ACPI `_DSM` function directly.
  acpi_call was only needed during initial debugging to manually
  power-cycle a GPU stuck in D3cold.

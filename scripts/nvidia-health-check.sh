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


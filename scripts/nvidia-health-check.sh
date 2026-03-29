#!/bin/bash

set -u

check_file() {
  if [ -e "$1" ]; then
    ls -l "$1"
  else
    echo "MISSING: $1"
  fi
}

echo "=== nvidia-smi ===" && nvidia-smi | head -9
echo ""
echo "=== Kernel modules ==="
lsmod | grep -E "nvidia|bbswitch"
echo ""
echo "=== modeset ===" && cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "N/A"
echo ""
echo "=== Runtime files ==="
check_file /usr/share/glvnd/egl_vendor.d/10_nvidia.json
check_file /usr/lib/x86_64-linux-gnu/libnvidia-tls.so.390.157
check_file /usr/lib/x86_64-linux-gnu/nvidia/xorg/extensions/libglx.so
check_file /etc/modprobe.d/gpu-optimus.conf
check_file /etc/modprobe.d/nvidia-force-id.conf
check_file /etc/bumblebee/xorg.conf.d/xorg.conf.nvidia
echo ""
echo "=== Bumblebee config ==="
grep -E '^(LibraryPath|XorgModulePath|XorgConfFile)=' /etc/bumblebee/bumblebee.conf 2>/dev/null || echo "MISSING: /etc/bumblebee/bumblebee.conf"
echo ""
echo "=== bumblebeed status ==="
systemctl is-active bumblebeed
echo ""
echo "=== Intel GLX ===" && glxinfo 2>/dev/null | grep renderer || echo "FAIL"
echo ""
echo "=== NVIDIA via optirun ==="
optirun glxinfo 2>/dev/null | grep renderer || echo "FAIL"

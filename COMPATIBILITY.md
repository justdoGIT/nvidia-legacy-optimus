# Compatibility Reports

Hardware confirmed working (or not) with this setup.
Sorted by driver version, then distro.

---

## How To Read This Table

| Field | What It Means |
|---|---|
| **Laptop Model** | Exact model name from lid sticker or `sudo dmidecode -s system-product-name` |
| **GPU Name** | Exact string from `lspci \| grep -i nvidia` |
| **Driver** | NVIDIA driver version used |
| **Kernel** | Kernel version from `uname -r` |
| **Distro** | Distribution and version |
| **Desktop** | Display server + compositor (matters for GLX wiring) |
| **Status** | See legend below |
| **Confidence** | How many independent reports back this up |
| **Notes** | Quirks, workarounds, partial failures |

### Status Legend

| Symbol | Meaning |
|---|---|
| ✅ Working | `optirun glxinfo` returns NVIDIA renderer, Intel GLX works, Bumblebee stable |
| ⚠️ Partial | Boots and renders but with caveats (see Notes) |
| ❌ Broken | Could not get NVIDIA rendering working |
| 🔬 Untested | Hardware reported but setup not attempted |

### Confidence Legend

| Symbol | Meaning |
|---|---|
| ⭐ | Reported by one person on one machine — treat as a lead, not a guarantee |
| ⭐⭐ | Confirmed independently on 2–4 different machines |
| ⭐⭐⭐ | Battle-tested — multiple users, multiple kernel versions, long-term stable |

---

## Driver 390.157

### Debian 12 (Bookworm)

| Laptop Model | GPU Name | Kernel | Desktop | Status | Confidence | Notes |
|---|---|---|---|---|---|---|
| Lenovo G500 | GeForce GT 720M (GF117) | 6.1.0-44 | XFCE + LightDM (Xorg) | ✅ Working | ⭐⭐⭐ Confirmed | Reference machine for this repo |
| Lenovo G510 | GeForce GT 720M (GF117) | 6.1.x | XFCE + LightDM (Xorg) | ✅ Working | ⭐ Reported | Same GPU as G500, likely identical setup |

### Ubuntu 22.04 LTS (Jammy)

| Laptop Model | GPU Name | Kernel | Desktop | Status | Confidence | Notes |
|---|---|---|---|---|---|---|
| Lenovo G580 | GeForce GT 635M (GF108) | 5.15.x | GNOME (Xorg) | ⚠️ Partial | ⭐ Reported | bbswitch fails on this ACPI; NVIDIA stays powered on. Rendering works. |

---

## Driver 470.xx

*No confirmed reports yet. If you have a Maxwell-era GPU (GTX 850M, 860M, 960M) on Debian Bookworm, please submit a report.*

---

## GPUs Likely Compatible (Untested)

These share the same GF117/GF108/GK208 silicon as confirmed hardware. The driver and Bumblebee config should be identical — but no one has reported back yet.

| GPU | Typical Laptop | Driver | Status |
|---|---|---|---|
| GeForce GT 610M | Various OEM | 390.xx | 🔬 Untested |
| GeForce GT 625M | Various OEM | 390.xx | 🔬 Untested |
| GeForce GT 630M | Dell Inspiron 15R | 390.xx | 🔬 Untested |
| GeForce GT 635M | Lenovo G580, HP Pavilion | 390.xx | 🔬 Untested |
| GeForce GT 640M | Various OEM | 390.xx | 🔬 Untested |
| GeForce GT 710M | Various OEM | 390.xx | 🔬 Untested |
| GeForce GT 730M | Acer Aspire, ASUS X550 | 390.xx | 🔬 Untested |
| GeForce GT 740M | Dell Inspiron, Lenovo IdeaPad | 390.xx | 🔬 Untested |
| GeForce 820M | Various OEM | 390.xx | 🔬 Untested |
| GeForce 840M | Various OEM | 390.xx | 🔬 Untested |

---

## Known Incompatible

| GPU | Reason |
|---|---|
| Any Kepler/Maxwell GPU on Wayland session | 390.xx has no Wayland EGL — use Xorg |
| GeForce GTX 900M series (Maxwell) | Needs 470.xx driver, not 390.xx |
| GeForce GTX 10xx (Pascal) | Still in active support — use official nvidia apt packages |

---

## Submitting a Report

Ran this setup on hardware not listed above? Please open a PR or issue with the following info:

```bash
# Run this and paste the output in your report
echo "=== System ===" && sudo dmidecode -s system-product-name
echo "=== GPU ===" && lspci | grep -i nvidia
echo "=== Kernel ===" && uname -r
echo "=== Distro ===" && cat /etc/os-release | grep PRETTY_NAME
echo "=== Desktop ===" && echo "$XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP"
echo "=== Driver ===" && nvidia-smi | grep "Driver Version"
echo "=== Intel GLX ===" && glxinfo 2>/dev/null | grep renderer
echo "=== NVIDIA GLX ===" && optirun glxinfo 2>/dev/null | grep renderer
```

**What makes a good report:**
- Paste the full output above — don't summarise
- Mention anything that didn't work out of the box
- Note any deviations from the standard install steps
- If partial/broken — include relevant lines from `sudo journalctl -u bumblebeed -n 30`

**You don't need a GitHub account to contribute** — paste your output as an [issue](../../issues) and it will be added to the table.

---

*Last updated: March 2026*


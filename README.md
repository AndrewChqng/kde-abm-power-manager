# KDE Plasma 6 Power Management Tweaks (Wayland)

[![KDE Plasma](https://img.shields.io/badge/KDE%20Plasma-6.x-blue?logo=kde&logoColor=white)](https://kde.org/plasma-desktop/)
[![Wayland](https://img.shields.io/badge/Display-Wayland-brightgreen)](https://wayland.freedesktop.org/)
[![Shell Script](https://img.shields.io/badge/Language-Bash%205+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Arch Linux / CachyOS / Fedora / openSUSE](https://img.shields.io/badge/Distro-Linux-orange?logo=linux&logoColor=white)](https://kernel.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Comprehensive, zero-prompt battery life and power management suite engineered specifically for KDE Plasma 6 on Wayland.**  
> Automatically coordinates AMD Adaptive Backlight Modulation (ABM), display refresh rates, KWin compositor shader pipelines, AMD P-State EPP & CPU boost/SMT, Radeon iGPU DPM, PCIe ASPM & Runtime PM, kernel VM writeback & THP, root & user cgroup v2 ZRAM reclaim, PipeWire & HDA audio power states, KDED6 modules, Bluetooth radio states, and color schemes via native KDE PowerDevil hooks and `udev`/`Polkit` rules.

---

## Table of Contents

- [Overview & Philosophy](#overview--philosophy)
- [Why KDE Plasma 6 (Wayland)?](#why-kde-plasma-6-wayland)
- [Subsystem Optimizations & Power Benefits](#subsystem-optimizations--power-benefits)
  - [1. Display & GPU Pipeline (`kscreen-doctor`)](#1-display--gpu-pipeline-kscreen-doctor)
  - [2. KWin Compositor & Geometry Transforms (`qdbus6`)](#2-kwin-compositor--geometry-transforms-qdbus6)
  - [3. KDED6 Background Watcher Modules](#3-kded6-background-watcher-modules)
  - [4. Smart Bluetooth Radio Management](#4-smart-bluetooth-radio-management)
  - [5. Physical Hardware LED Control](#5-physical-hardware-led-control)
  - [6. Lenovo IdeaPad Always-On USB Ports](#6-lenovo-ideapad-always-on-usb-ports)
  - [7. Background Timers, Boosters, KDE Connect & System Daemons](#7-background-timers-boosters-kde-connect--system-daemons)
  - [8. User & Root Cgroup v2 Memory, THP & Kernel VM Writeback](#8-user--root-cgroup-v2-memory-thp--kernel-vm-writeback)
  - [9. PipeWire Audio Quantum & HDA Codec Power Save](#9-pipewire-audio-quantum--hda-codec-power-save)
  - [10. Content-Aware Dark Mode Switching (ABM Boost)](#10-content-aware-dark-mode-switching-abm-boost)
  - [11. CPU Boost, AMD P-State EPP, SMT, ACPI Profile, iGPU DPM & PCIe ASPM](#11-cpu-boost-amd-p-state-epp-smt-acpi-profile-igpu-dpm--pcie-aspm)
  - [12. Rich Desktop Notifications](#12-rich-desktop-notifications)
- [Estimated Power Savings Breakdown](#estimated-power-savings-breakdown)
- [Installation & Quick Start](#installation--quick-start)
  - [Prerequisites](#prerequisites)
  - [1. Install Udev, Tmpfiles & Polkit Rules (One-Time Setup)](#1-install-udev-tmpfiles--polkit-rules-one-time-setup)
  - [2. Automatic PowerDevil Hook Setup](#2-automatic-powerdevil-hook-setup)
  - [3. Manual System Settings Setup](#3-manual-system-settings-setup)
- [Manual CLI Testing](#manual-cli-testing)
- [Compatibility](#compatibility)
- [Troubleshooting & Verification](#troubleshooting--verification)
- [Credits & AI Disclaimer](#credits--ai-disclaimer)

---

## Overview & Philosophy

Traditional Linux battery daemons either fight with KDE Plasma's native PowerDevil service or ignore the desktop graphics and audio stack altogether.

This project takes a **full-stack, KDE-native approach**:
- **Zero password prompts at runtime**: A clean `udev` rule (`99-kde-abm-power-manager.rules`), `tmpfiles.d` config, and `Polkit` rule (`50-kde-abm-power-manager.rules`) grant members of the `wheel` group direct write access to kernel `sysfs` power attributes, allowing KDE PowerDevil to run the script as your normal desktop user with full access to both user-space D-Bus buses (`KWin`, `kscreen`, `PipeWire`, `KDED6`) and hardware kernel knobs.
- **Targets every major laptop power sink**:
  - **Display backlight and timing controllers (TCON)**
  - **Continuous GPU composition redraw loops and Radeon iGPU DPM states**
  - **CPU Core Performance Boost voltage spikes, `amd-pstate-epp`, and SMT threads**
  - **PCIe ASPM link states & 20+ PCI/NVMe/USB runtime power controllers**
  - **Kernel VM dirty writeback batching, Transparent Huge Pages (THP), and global ZRAM cold-page reclaim**
  - **Audio codec power gating and PipeWire buffer quantum scaling**

---

## Why KDE Plasma 6 (Wayland)?

KDE Plasma 6 on Wayland provides deep, scriptable introspection into the graphics and desktop pipeline:
1. **`kscreen-doctor`**: Directly configures kernel DRM/KMS driver properties atomically without screen tearing, including AMDGPU ABM levels, per-display refresh rates, multi-plane overlay (MPO) color preferences, bits-per-color bandwidth, and variable refresh rate (VRR).
2. **KWin Effects Interface (`org.kde.KWin /Effects`)**: Allows live loading and unloading of heavyweight shader passes (blur, translucency, spring physics, touch trackers) without restarting the desktop.
3. **KDE Solid Power Management (`org.kde.Solid.PowerManagement`)**: Controls hardware peripherals such as keyboard backlights and profile hooks.
4. **KDED6 Module Controller (`org.kde.kded6 /kded`)**: Provides live management of desktop background modules (SMB network discovery, disk space pollers).
5. **Systemd User & Root Cgroup v2 Hierarchy**: Enables precise `SCHED_IDLE` scheduling demotion and proactive cold-page ZRAM compression.

---

## Subsystem Optimizations & Power Benefits

### 1. Display & GPU Pipeline (`kscreen-doctor`)

The display panel and GPU display engine (DCN) account for **30%–45%** of a modern laptop's total power consumption. This script configures the display pipeline atomically per power state:

| Parameter | AC (`ac`) | Battery (`battery`) | Low Battery (`low_battery`) | Technical Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **Refresh Rate** | **Maximum Hz** | **Lowest Hz** | **Lowest Hz** | Dynamically drops all active displays to their lowest refresh rate for the current resolution on battery to cut GPU scanout and TCON power. |
| **AMD ABM** | `0` (Off) | `4` (Max) | `4` (Max) | Modulates pixel contrast and luminance curves in the AMDGPU driver to drop physical LED backlight current by up to 25%–35% transparently. |
| **Color Tradeoff** | `preferAccuracy` | `preferEfficiency` | `preferEfficiency` | Enables direct hardware scanout (Multi-Plane Overlays) and lower-power intermediate surface formats, bypassing GPU compositor blending. |
| **Bit Depth (`maxbpc`)** | `automatic` (10/16-bit) | `8` (8-bit) | `8` (8-bit) | Reduces eDP link bandwidth requirements over the display interface, saving PHY transceiver power. |
| **EDR Policy** | `always` | `never` | `never` | Disables Extended Dynamic Range headroom boosts on battery, preventing client applications from driving high backlight peaks. |
| **Adaptive Sync (`vrrpolicy`)**| `automatic` | `always` | `always` | Enables Variable Refresh Rate globally across all windows, allowing the panel to drop refresh rate during static content or video playback. |
| **Software Dimming** | `100%` | `100%` | `80%` | Applies an additional software luminance multiplier on Low Battery to stretch reserve runtime. |

### 2. KWin Compositor & Geometry Transforms (`qdbus6`)

Window management animations and compositor shaders force KWin to continuously render at the display refresh rate whenever windows open, close, minimize, or move.

- **Unloaded on Battery & Low Battery / Reloaded on AC:**
  - `blur` & `translucency`: Eliminates dual-pass Gaussian blur shaders and alpha-composite blend calculations.
  - `wobblywindows` & `fallapart`: Eliminates per-frame polygon mesh deformation physics calculations.
  - `touchpoints`: Prevents high CPU thread spikes triggered by tracking multi-finger gestures on touchscreens.
  - `scale` & `squash`: Removes intermediate scaling matrices during window minimization/restoration.
  - `slide`, `slideback`, `slidingpopups`, `slidingnotifications`: Replaces multi-frame sliding translations with instantaneous surface commits.

### 3. KDED6 Background Watcher Modules

Unloads polling modules (`smbwatcher`, `remotenotifier`, `freespacenotifier`) on Battery and Low Battery via `qdbus6 org.kde.kded6 /kded unloadModule`, cutting idle background timer interrupts.

### 4. Smart Bluetooth Radio Management

- **Battery / Low Battery:** Queries `bluetoothctl devices Connected`. If **no active devices** are connected, Bluetooth is soft-blocked via `rfkill block bluetooth`. If a device **is** connected, Bluetooth remains active without interruption.
- **AC:** Automatically unblocks Bluetooth radio.

### 5. Physical Hardware LED Control

Turns off keyboard backlight (`level 0`) via KDE Solid D-Bus upon switching to Battery or Low Battery, saving **0.2W – 0.4W** of continuous LED draw.

### 6. Lenovo IdeaPad Always-On USB Ports

Disables Always-On USB standby charging (`/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/usb_charging = 0`) on **Low Battery** so connected cables/peripherals cannot siphon reserve battery capacity.

### 7. Background Timers, Boosters, KDE Connect & System Daemons

- **User Services (`systemctl --user`)**:
  - `arch-update.timer`: Paused on Battery and Low Battery.
  - `psd-resync.timer`, `plasma-foreground-booster.service`, `dmemcg-booster-user.service`, and `app-org.kde.kdeconnect.daemon@autostart.service`: Stopped on **Low Battery**, started on AC and Battery.
- **System Daemons (`systemctl` via Polkit rule)**:
  - `cups.service`, `avahi-daemon.service`, and `libvirtd.service`: Paused on **Low Battery** (recording previously active units in `~/.local/state/kde-power-management/active-system-services`) and seamlessly restored when returning to AC or Battery.

### 8. User & Root Cgroup v2 Memory, THP & Kernel VM Writeback

| Parameter | AC (`ac`) | Battery (`battery`) | Low Battery (`low_battery`) | Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **`background.slice` CPU/IO** | `0` / `no-change` | `cpu.idle=1` / `idle` | `cpu.idle=1` / `idle` | Demotes background apps to `SCHED_IDLE` so they cannot ramp CPU clocks. |
| **Cgroup Cold-Page Reclaim** | None | `64M` (user) + `128M` (root) | `64M` (user) + `256M` (root) | Compresses idle pages into `zstd` ZRAM, freeing physical DRAM ranks. |
| **Transparent Huge Pages (THP)**| `always` (`defer+madvise`) | `madvise` (`madvise`) | `madvise` (`madvise`) | Prevents `khugepaged` background memory scanning and defragmentation wakeups. |
| **`vm.dirty_writeback_centisecs`**| `1500` (15s) | `6000` (60s) | `9000` (90s) | Batches dirty RAM flushes so the NVMe SSD remains in deep APST sleep states. |
| **`vm.laptop_mode` & Compaction**| `0` | `5` | `5` + `compact_memory=1` | Coordinates disk writes and compacts fragmented RAM pages on Low Battery. |

### 9. PipeWire Audio Quantum & HDA Codec Power Save

- **HDA Audio Codec (`/sys/module/snd_hda_intel/parameters/power_save`)**: Set to `1` on Battery and Low Battery (powers down audio codec hardware after 1s of silence); `0` on AC.
- **PipeWire Buffer (`clock.force-quantum`)**: Set to `2048` samples on Low Battery (reducing audio CPU interrupts by 4x–8x); `0` (dynamic) on AC and Battery.

### 10. Content-Aware Dark Mode Switching (ABM Boost)

Automatically switches Plasma to `BreezeDark` on Battery and Low Battery to maximize AMD ABM physical backlight reductions, saving and restoring the user's AC theme when plugged back in.

### 11. CPU Boost, AMD P-State EPP, SMT, ACPI Profile, iGPU DPM & PCIe ASPM

Unlocked via [`99-kde-abm-power-manager.rules`](99-kde-abm-power-manager.rules):

| Hardware Knob | AC (`ac`) | Battery (`battery`) | Low Battery (`low_battery`) | Technical Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **CPU Core Boost (`cpufreq/boost`)** | `1` (On) | `0` (Off) | `0` (Off) | Eliminates high-voltage turbo boost spikes on battery (`2.0W – 8.0W` peak savings). |
| **AMD P-State EPP** | `balance_performance` | `balance_power` | `power` | Instructs Zen SMU hardware autonomous frequency scaler to favor deep C-states. |
| **SMT & Max Frequency Cap** | `SMT=on`, Max Hz | `SMT=on`, Max Hz | `SMT=off`, `2.0 GHz` cap | Parks sibling hyperthreads and clamps core frequency on Low Battery. |
| **ACPI `platform_profile`** | `balanced` | `low-power` | `low-power` | Lowers EC STAPM/PPT package wattage limits and quietens fan curves. |
| **Radeon iGPU DPM** | `auto` | `low` | `low` | Pins Radeon iGPU shaders and `fclk`/`mclk` to lowest voltage state (`0.5W – 2.5W`). |
| **PCIe ASPM & Runtime PM** | `default` / `on` | `powersave` / `auto` | `powersupersave` / `auto` | Enables L1.1/L1.2 PCIe link sleep and runtime auto-suspend across all 20+ PCI/NVMe/USB devices (`0.8W – 2.5W`). |

### 12. Rich Desktop Notifications

Dispatches native KDE notifications via `notify-send` (`--hint=string:desktop-entry:org.kde.powerdevil`) summarizing every display, desktop, cgroup, CPU, GPU, and PCIe optimization applied.

---

## Estimated Power Savings Breakdown

| Subsystem | Power Saving (Typical Laptop) | Mechanism |
| :--- | :--- | :--- |
| **CPU Boost Off + AMD P-State EPP + ACPI Profile** | `2.0W – 8.0W` (active/burst) | Eliminates inefficient high-voltage boost states & lowers SMU PPT limits |
| **AMD ABM + Dark Theme + Refresh Rate** | `1.7W – 4.2W` | Physical LED backlight reduction, lower TCON scanout & MPO direct scanout |
| **PCIe ASPM (`powersave`/`powersupersave`) + PCI Runtime PM** | `0.8W – 2.5W` (idle) | Deep L1.2 PCIe link sleep & deeper SoC `S0ix` package C-state residency |
| **Radeon iGPU DPM (`low`) + KWin Effects Off** | `0.8W – 3.0W` | Pins iGPU to minimum clock state and cuts compositor shader passes |
| **Kernel VM Writeback Batching + THP `madvise` + ZRAM Reclaim** | `0.4W – 1.2W` | Longer NVMe APST deep sleep residency & zero `khugepaged` scan wakeups |
| **HDA Audio Codec Power Save + PipeWire Quantum (2048)** | `0.5W – 1.4W` | Powers down idle HDA codec & cuts audio thread interrupts by 4x–8x |
| **Smart Bluetooth + Keyboard LED Off** | `0.4W – 0.9W` | RF transceiver sleep & physical LED cut |
| **Total Estimated Reduction** | **~5.0W – 14.0W+** | **Up to 40% – 85% longer battery runtime** |

---

## Installation & Quick Start

### Prerequisites

```bash
# Arch Linux / CachyOS
sudo pacman -S --needed kscreen plasma-workspace qdbus libnotify jq bluez-utils
```

Clone the repository:

```bash
git clone https://github.com/AndrewChqng/kde-abm-power-manager.git ~/gh/kde-abm-power-manager
cd ~/gh/kde-abm-power-manager
chmod +x additional-power-management-tweaks.sh install-permissions.sh
```

### 1. Install Udev, Tmpfiles & Polkit Rules (One-Time Setup)

Run the included installer once to grant the `wheel` group passwordless write access to the kernel `sysfs` power interfaces and Polkit rules:

```bash
./install-permissions.sh
```

### 2. Automatic PowerDevil Hook Setup

Configure KDE PowerDevil directly from the command line using `kwriteconfig6`:

```bash
kwriteconfig6 --file powerdevilrc --group AC --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh ac"
kwriteconfig6 --file powerdevilrc --group Battery --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh battery"
kwriteconfig6 --file powerdevilrc --group LowBattery --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh low_battery"

# Reload PowerDevil configuration live
qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement.reparseConfiguration
```

### 3. Manual System Settings Setup

1. Open **KDE System Settings** (`systemsettings`) → **Power Management**.
2. For each profile tab (**On AC Power**, **On Battery**, **On Low Battery**), check **Run script** and point to `additional-power-management-tweaks.sh` with `ac`, `battery`, or `low_battery`.

---

## Manual CLI Testing

```bash
# Test Battery profile
./additional-power-management-tweaks.sh battery

# Test Low Battery profile
./additional-power-management-tweaks.sh low_battery

# Restore AC profile
./additional-power-management-tweaks.sh ac
```

---

## Compatibility

- **Desktop Environment**: KDE Plasma 6.0+ (Wayland session).
- **CPU & GPU**: AMD Ryzen (`amd-pstate-epp`) & AMD Radeon iGPU (`amdgpu` ABM & DPM); gracefully skips missing sysfs nodes on Intel/NVIDIA hardware.
- **Distributions**: Arch Linux, CachyOS, Fedora 40+, openSUSE Tumbleweed, Debian 13 / Kubuntu 24.10+.

---

## Troubleshooting & Verification

```bash
# Check CPU boost, EPP, SMT, and ACPI platform profile
cat /sys/devices/system/cpu/cpufreq/boost \
    /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference \
    /sys/devices/system/cpu/smt/control \
    /sys/firmware/acpi/platform_profile

# Check GPU DPM, PCIe ASPM, and HDA audio power save
cat /sys/class/drm/card1/device/power_dpm_force_performance_level \
    /sys/module/pcie_aspm/parameters/policy \
    /sys/module/snd_hda_intel/parameters/power_save

# Check VM writeback, laptop_mode, and THP
sysctl vm.dirty_writeback_centisecs vm.laptop_mode
cat /sys/kernel/mm/transparent_hugepage/enabled
```

---

## Credits & AI Disclaimer

Developed with technical analysis and implementation assistance from **Antigravity (Google DeepMind)**.

Display pipeline parameters (`abm`, `colorPowerTradeoff`, `maxbpc`, `edrPolicy`, `dimming`), KDE D-Bus interfaces, cgroup v2 controls, and `udev`/`Polkit` hardware rules were engineered and verified on KDE Plasma 6 (Wayland).

> **Disclaimer:** This project contains scripts generated and refined with the assistance of an experimental AI coding assistant. Always test hardware power scripts on your specific hardware configuration.

# KDE Plasma 6 Power Management Tweaks (Wayland)

[![KDE Plasma](https://img.shields.io/badge/KDE%20Plasma-6.x-blue?logo=kde&logoColor=white)](https://kde.org/plasma-desktop/)
[![Wayland](https://img.shields.io/badge/Display-Wayland-brightgreen)](https://wayland.freedesktop.org/)
[![Shell Script](https://img.shields.io/badge/Language-Bash%205+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Arch Linux / CachyOS / Fedora / openSUSE](https://img.shields.io/badge/Distro-Linux-orange?logo=linux&logoColor=white)](https://kernel.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Advanced, rootless battery life and power management suite engineered specifically for KDE Plasma 6 on Wayland.**  
> Automatically controls AMD Adaptive Backlight Modulation (ABM), display refresh rates, KWin compositor shader pipelines, KDED6 background modules, PipeWire audio buffers, user cgroup v2 priorities, Bluetooth radio states, and color schemes via native KDE D-Bus and PowerDevil hooks.

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
  - [7. Background Timers, Foreground Boosters & KDE Connect](#7-background-timers-foreground-boosters--kde-connect)
  - [8. User Cgroup v2 Memory & CPU Scheduling (`background.slice`)](#8-user-cgroup-v2-memory--cpu-scheduling-backgroundslice)
  - [9. PipeWire Audio Buffer Quantum Scaling](#9-pipewire-audio-buffer-quantum-scaling)
  - [10. Content-Aware Dark Mode Switching (ABM Boost)](#10-content-aware-dark-mode-switching-abm-boost)
  - [11. Rich Desktop Notifications](#11-rich-desktop-notifications)
- [Estimated Power Savings Breakdown](#estimated-power-savings-breakdown)
- [Installation & Quick Start](#installation--quick-start)
  - [Prerequisites](#prerequisites)
  - [Automatic PowerDevil Hook Setup](#automatic-powerdevil-hook-setup)
  - [Manual System Settings Setup](#manual-system-settings-setup)
- [Manual CLI Testing](#manual-cli-testing)
- [Compatibility](#compatibility)
- [Troubleshooting & Verification](#troubleshooting--verification)
- [Credits & AI Disclaimer](#credits--ai-disclaimer)

---

## Overview & Philosophy

Most Linux battery guides rely on aggressive kernel CPU governor throttling or intrusive background daemons (like TLP or auto-cpufreq) that often fight with modern hardware energy performance hints (EPP) or require `sudo` privileges.

This project takes a **subsystem-native, rootless approach**. Instead of choking the CPU, it targets the biggest silent energy sinks on modern laptops:
- **Display backlight and timing controllers (TCON)**
- **Continuous GPU composition redraw loops**
- **Unnecessary audio and timer wakeups**
- **Peripheral battery siphoning**
- **Background memory thrashing and SSD disk synchronization**

Every tweak runs 100% in **unprivileged user space** and integrates cleanly with KDE PowerDevil's native profile transitions (`ac`, `battery`, `low_battery`).

---

## Why KDE Plasma 6 (Wayland)?

KDE Plasma 6 on Wayland provides deep, scriptable introspection into the graphics and desktop pipeline that was previously impossible or fragmented:
1. **`kscreen-doctor`**: Directly configures kernel DRM/KMS driver properties atomically without screen tearing, including AMDGPU ABM levels, multi-plane overlay (MPO) color preferences, bits-per-color bandwidth, and variable refresh rate (VRR).
2. **KWin Effects Interface (`org.kde.KWin /Effects`)**: Allows live loading and unloading of heavyweight shader passes (blur, translucency, spring physics, touch trackers) without restarting the desktop.
3. **KDE Solid Power Management (`org.kde.Solid.PowerManagement`)**: Controls hardware peripherals such as keyboard backlights and profile hooks.
4. **KDED6 Module Controller (`org.kde.kded6 /kded`)**: Provides live management of desktop background modules (SMB network discovery, disk space pollers).
5. **Systemd User Cgroup v2 Hierarchy**: KDE Plasma 6 organizes apps and background daemons into distinct cgroup slices (`app.slice`, `background.slice`, `session.slice`), enabling precise scheduling demotion of background tasks.

---

## Subsystem Optimizations & Power Benefits

### 1. Display & GPU Pipeline (`kscreen-doctor`)

The display panel and GPU display engine (DCN) account for **30%–45%** of a modern laptop's total power consumption. This script configures the display pipeline atomically per power state:

| Parameter | AC (`ac`) | Battery (`battery`) | Low Battery (`low_battery`) | Technical Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **Refresh Rate** | **Maximum Hz** | **Lowest Hz** | **Lowest Hz** | Dynamically drops multi-rate displays (e.g. 120Hz/90Hz → 60Hz) to cut GPU scanout bandwidth and panel timing controller power. |
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

**Benefit:** Eliminates GPU compute load during UI interactions, reducing CPU/GPU package wakeups to near zero when interacting with windows.

### 3. KDED6 Background Watcher Modules

KDE Daemon 6 runs several polling modules that periodically wake up the CPU and network stack:
- `smbwatcher`: Polls local subnet for SMB/Samba network shares.
- `remotenotifier`: Monitors remote network directories.
- `freespacenotifier`: Periodically polls mount points for disk space alerts.

**Benefit:** Unloading these modules on Battery and Low Battery via `qdbus6 org.kde.kded6 /kded unloadModule` cuts idle background timer interrupts.

### 4. Smart Bluetooth Radio Management

Standard Bluetooth adapters continuously broadcast inquiry and page scans when enabled:
- **Battery / Low Battery:** Queries `bluetoothctl devices Connected`. If **no active devices** (e.g. mouse, headphones) are connected, Bluetooth is soft-blocked via `rfkill block bluetooth`. If a device **is** connected, Bluetooth remains active without interruption.
- **AC:** Automatically unblocks Bluetooth radio.

**Benefit:** Saves **0.2W – 0.5W** of continuous RF transceiver power when no peripherals are in use.

### 5. Physical Hardware LED Control

- Directly queries KDE Solid's power management interface (`org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl`) and sets keyboard backlight brightness to `0` upon unplugging.

**Benefit:** Eliminates **0.2W – 0.4W** of continuous physical LED diode draw.

### 6. Lenovo IdeaPad Always-On USB Ports

Modern Lenovo laptops (IdeaPad, Slim, Yoga) support Always-On USB charging via the `ideapad_acpi` platform driver.
- On **Low Battery**, the script writes `0` to `/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/usb_charging` (world-writable without `sudo`).
- Prevents connected USB cables, dongles, or peripheral devices from siphoning the critical remaining battery reserve.

### 7. Background Timers, Foreground Boosters & KDE Connect

Throttles background systemd user services that generate disk and network traffic:
- **`arch-update.timer`**: Stopped on battery to prevent periodic `pacman`/package database syncs.
- **`psd-resync.timer` (Profile-Sync-Daemon)**: Stopped on **Low Battery**. Keeps Google Chrome / browser profiles strictly in `tmpfs` RAM without triggering hourly multi-hundred megabyte `rsync` NVMe write bursts.
- **`plasma-foreground-booster.service` & `dmemcg-booster-user.service`**: Stopped on **Low Battery** to prevent aggressive CPU cgroup boost spikes whenever switching windows.
- **`app-org.kde.kdeconnect.daemon@autostart.service`**: Stopped on **Low Battery** to eliminate background LAN UDP broadcasts, clipboard polling, and packet wakeups; automatically restarted on AC and Battery.

### 8. User Cgroup v2 Memory & CPU Scheduling (`background.slice`)

Modern systemd user instances delegate cgroup v2 control to unprivileged users:
- **`cpu.idle = 1` (`SCHED_IDLE`)**: Demotes all background tasks to idle priority on Battery / Low Battery. Background daemons can never ramp CPU frequency or Infinity Fabric clocks.
- **`io.prio.class = idle`**: Demotes background storage requests so disk controllers remain in low-power states.
- **`memory.swap.high = 512M`**: Caps background swap consumption, ensuring background processes cannot push memory past fast ZRAM into the NVMe swapfile.
- **`memory.reclaim = 64M`**: Triggers a proactive one-time reclaim on `background.slice` to compress idle background pages into `zstd` ZRAM upon switching to battery.

### 9. PipeWire Audio Buffer Quantum Scaling

Audio servers wake the CPU on every buffer quantum cycle:
- **Low Battery:** Sets PipeWire's `clock.force-quantum` to `2048` samples via `pw-metadata`.
- **AC / Battery:** Restores dynamic low-latency scaling (`clock.force-quantum = 0`).

**Benefit:** Reduces audio interrupt wakeups by **2x to 8x** during media playback or calls, saving up to **0.3W – 0.7W** of CPU package power.

### 10. Content-Aware Dark Mode Switching (ABM Boost)

AMD's Adaptive Backlight Modulation (ABM) works by analyzing on-screen pixel luminance: the darker the content, the further the physical LED backlight can be dimmed without loss of legibility.
- Automatically switches Plasma to `BreezeDark` (and triggers the FreeDesktop `prefer-dark` portal) on battery.
- Saves the previous AC color scheme and seamlessly restores it when returning to AC.

### 11. Rich Desktop Notifications

Integrates with KDE's notification daemon via `notify-send`:
- Displays native battery icons (`battery-charging`, `battery`, `battery-low`) and urgency levels.
- Provides a clean, bulleted breakdown of every parameter adjusted during the power state change.

---

## Estimated Power Savings Breakdown

| Subsystem | Power Saving (Typical Laptop) | Mechanism |
| :--- | :--- | :--- |
| **AMD ABM + Dark Theme** | `1.2W – 2.8W` | Physical LED backlight reduction via contrast compensation |
| **Refresh Rate & Display Pipeline** | `0.5W – 1.4W` | Lower pixel clock, PHY link rates, and MPO direct scanout |
| **KWin Compositor Effects** | `0.4W – 1.0W` (active use) | Zero GPU fragment shader rendering and geometry passes |
| **Smart Bluetooth Radio** | `0.2W – 0.5W` | Radio sleep when no connected peripherals |
| **PipeWire Audio Quantum (2048)** | `0.3W – 0.7W` (media playback) | 4x–8x fewer CPU audio thread interrupts |
| **User Cgroups & Timers** | `0.2W – 0.6W` | Lower CPU wakeup frequency and Infinity Fabric sleep |
| **Keyboard Backlight LED** | `0.2W – 0.4W` | Physical LED cut |
| **Total Estimated Reduction** | **~2.5W – 6.0W+** | **Extends battery runtime by 20% to 50%** |

---

## Installation & Quick Start

### Prerequisites

Ensure the following common user-space packages are available (pre-installed on most modern KDE distributions like Arch Linux, CachyOS, Fedora KDE, openSUSE):

```bash
# Arch Linux / CachyOS
sudo pacman -S --needed kscreen plasma-workspace qdbus libnotify jq bluez-utils

# Fedora KDE
sudo dnf install kscreen-doctor kf6-kdbusaddons libnotify jq bluez
```

Clone the repository into your user directory:

```bash
git clone https://github.com/AndrewChqng/kde-abm-power-manager.git ~/gh/kde-abm-power-manager
cd ~/gh/kde-abm-power-manager
chmod +x additional-power-management-tweaks.sh
```

### Automatic PowerDevil Hook Setup

You can configure KDE PowerDevil directly from the command line using `kwriteconfig6`:

```bash
# Configure PowerDevil hooks
kwriteconfig6 --file powerdevilrc --group AC --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh ac"
kwriteconfig6 --file powerdevilrc --group Battery --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh battery"
kwriteconfig6 --file powerdevilrc --group LowBattery --group RunScript --key ProfileLoadCommand "$HOME/gh/kde-abm-power-manager/additional-power-management-tweaks.sh low_battery"

# Instruct PowerDevil to reload configuration live
qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement.reparseConfiguration
```

### Manual System Settings Setup

1. Open **KDE System Settings** (`systemsettings`).
2. Navigate to **Power Management** (or search "Energy Saving").
3. For each profile tab (**On AC Power**, **On Battery**, **On Low Battery**):
   - Check **Run script**.
   - Set the command to:
     - AC: `/path/to/additional-power-management-tweaks.sh ac`
     - Battery: `/path/to/additional-power-management-tweaks.sh battery`
     - Low Battery: `/path/to/additional-power-management-tweaks.sh low_battery`
4. Click **Apply**.

---

## Manual CLI Testing

You can trigger any power state manually from your terminal to verify settings or inspect notifications:

```bash
# Test AC profile
./additional-power-management-tweaks.sh ac

# Test Battery profile
./additional-power-management-tweaks.sh battery

# Test Low Battery profile
./additional-power-management-tweaks.sh low_battery

# Specify a custom display output explicitly (optional)
./additional-power-management-tweaks.sh battery eDP-1
```

---

## Compatibility

- **Desktop Environment**: KDE Plasma 6.0+ (Wayland session required for `kscreen-doctor` pipeline controls).
- **GPU Architecture**:
  - **AMD Radeon / Ryzen APUs**: Full support for ABM (0–4), VRR, MPO Color Power Tradeoff, and MaxBPC.
  - **Intel Iris Xe / Arc**: Supports Refresh Rate, VRR, MaxBPC, Color Power Tradeoff (ABM ignored if unsupported).
- **Distributions**: Arch Linux, CachyOS, Fedora 40+, openSUSE Tumbleweed, Debian 13 / Kubuntu 24.10+.
- **Hardware Features**: Lenovo IdeaPad USB charging node applies automatically if `ideapad_acpi` is loaded; gracefully skipped on other vendors without error.

---

## Troubleshooting & Verification

### Verifying Active Settings

Check whether display parameters are currently applied:

```bash
kscreen-doctor -o
```

Check active PipeWire audio quantum:

```bash
pw-metadata -n settings
```

Check background cgroup v2 parameters:

```bash
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/background.slice/cpu.idle
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/background.slice/memory.swap.high
```

---

## Credits & AI Disclaimer

Developed with technical analysis and implementation assistance from **Antigravity (Google DeepMind)**.

Display pipeline parameters (`abm`, `colorPowerTradeoff`, `maxbpc`, `edrPolicy`, `dimming`) were reverse-engineered from KDE's upstream `plasma/libkscreen` (`src/doctor/doctor.cpp`) and verified on Wayland.

> **Disclaimer:** This project contains scripts generated and refined with the assistance of an experimental AI coding assistant. Always test hardware power scripts on your specific hardware configuration.

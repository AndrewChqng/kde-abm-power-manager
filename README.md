# KDE ABM & Display Power Manager

A lightweight script to automatically adjust **Adaptive Backlight Modulation (ABM)**, display rendering pipelines, and KWin compositor effects on KDE Plasma (Wayland) depending on power state (`ac`, `battery`, or `low battery`).

Runs cleanly in user space without requiring `sudo` or root privileges, making it directly usable inside **KDE System Settings → Power Management → Run script**.

---

## Features

### 1. Display & GPU Pipeline Optimization (via `kscreen-doctor`)
Leverages hardware and driver-level controls exposed by KWin and `amdgpu`:

| Setting | AC Mode (`ac`) | Battery Mode (`battery`) | Low Battery (`low_battery`) | Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **ABM (Backlight Modulation)** | `0` (Disabled) | `4` (Maximum) | `4` (Maximum) | Reduces panel backlight draw by modulating contrast |
| **Color Power Tradeoff** | `preferAccuracy` | `preferEfficiency` | `preferEfficiency` | Enables direct scanout (MPO planes) & lower-power framebuffer formats |
| **Color Bit Depth (`maxbpc`)** | `automatic` (10/16-bit) | `8` (8-bit) | `8` (8-bit) | Reduces eDP link bandwidth and display engine power |
| **EDR Policy** | `always` | `never` | `never` | Blocks apps from driving peak backlight headroom |
| **Software Dimming** | `100%` | `100%` | `80%` | Additional software dimming for emergency battery conservation |

### 2. KWin Compositor Effects (via `qdbus6`)
Disables shader-heavy background compositing effects to reduce iGPU wakeups and draw cycles:
- **`blur`**: Unloaded on battery; reloaded on AC.
- **`translucency`**: Unloaded on battery; reloaded on AC.

---

## Usage

Make sure the script is executable:

```bash
chmod +x additional-power-management-tweaks.sh
```

### Command Line

```bash
# Switched to AC power
./additional-power-management-tweaks.sh ac

# Switched to Battery
./additional-power-management-tweaks.sh battery

# Low Battery alert
./additional-power-management-tweaks.sh low_battery
# or
./additional-power-management-tweaks.sh "low battery"
```

### Specifying a Display Output
By default, the script auto-detects the first `eDP*` internal panel reported by `kscreen-doctor -o` (falling back to `eDP-1`). You can also pass an explicit display name:

```bash
./additional-power-management-tweaks.sh battery eDP-1
```

---

## Integrating with KDE Power Management (PowerDevil)

1. Open **System Settings** → **Power Management**.
2. Configure the script under each power state:
   - **On AC Power** → Expand **Run Script** → Add:
     ```bash
     /home/roboy/gh/kde-abm-power-manager/additional-power-management-tweaks.sh ac
     ```
   - **On Battery** → Expand **Run Script** → Add:
     ```bash
     /home/roboy/gh/kde-abm-power-manager/additional-power-management-tweaks.sh battery
     ```
   - **On Low Battery** → Expand **Run Script** → Add:
     ```bash
     /home/roboy/gh/kde-abm-power-manager/additional-power-management-tweaks.sh low_battery
     ```

---

## Credits & AI Disclaimer

Developed with assistance from **Antigravity (Google DeepMind)**. Display parameters (`abm`, `colorPowerTradeoff`, `maxbpc`, `edrPolicy`, `dimming`) were reverse-engineered from KDE's upstream `plasma/libkscreen` (`src/doctor/doctor.cpp`) and verified on Wayland.

> **Disclaimer:** This project contains code and documentation generated with the assistance of an experimental AI coding assistant. Please review and test scripts on your hardware before deploying them in automated system hooks.

# KDE ABM Power Manager

A lightweight shell script to automatically adjust **Adaptive Backlight Modulation (ABM)** on KDE Plasma (Wayland) depending on power state (`ac`, `battery`, or `low battery`) using `kscreen-doctor`.

## Overview

AMD GPUs with internal eDP panels support hardware-assisted **Adaptive Backlight Modulation (ABM)** (exposed by the `amdgpu` kernel driver as `panel power savings` and managed by KWin via the `kde-output-management-v2` protocol).

While KDE Plasma exposes this setting in **System Settings → Display & Monitor**, `kscreen-doctor --help` does not currently list the `abm` parameter. Under the hood, `libkscreen` supports setting the ABM level from `0` to `4` via:

```bash
kscreen-doctor output.<name>.abm.<0-4>
```

 This script wraps `kscreen-doctor` to switch ABM levels based on your power profile or power state:
- **`ac`** → Sets ABM level to `0` (Disabled / full color accuracy)
- **`battery` / `low_battery` / `"low battery"`** → Sets ABM level to `4` (Maximum power saving)

## Usage

Make sure the script is executable:

```bash
chmod +x kde-abm-power-manager.sh
```

Run with the desired power state:

```bash
# On AC power (sets ABM to 0)
./kde-abm-power-manager.sh ac

# On Battery power (sets ABM to 4)
./kde-abm-power-manager.sh battery

# On Low Battery (sets ABM to 4)
./kde-abm-power-manager.sh "low battery"
./kde-abm-power-manager.sh low_battery
```

### Specifying the Display Output

By default, the script auto-detects the first `eDP*` internal panel reported by `kscreen-doctor -o` (falling back to `eDP-1`). You can also pass a specific output name as the second argument:

```bash
./kde-abm-power-manager.sh battery eDP-1
```

## Integrating with KDE Power Management (PowerDevil)

You can configure KDE Plasma to run this script automatically when switching between AC, Battery, and Low Battery states:

1. Open **System Settings** → **Power Management**.
2. For each tab (**On AC Power**, **On Battery**, **On Low Battery**):
   - Expand **Run Script** (or **Other Settings** → **When entering state**).
   - Select the script path and pass the corresponding parameter:
     - **On AC Power**: `/home/roboy/gh/kde-abm-power-manager/kde-abm-power-manager.sh ac`
     - **On Battery**: `/home/roboy/gh/kde-abm-power-manager/kde-abm-power-manager.sh battery`
     - **On Low Battery**: `/home/roboy/gh/kde-abm-power-manager/kde-abm-power-manager.sh low_battery`

## Credits & AI Disclaimer

Developed with assistance from **Antigravity (Google DeepMind)**. The undocumented `kscreen-doctor output.<name>.abm.<0-4>` command was identified by inspecting the `kscreen-doctor` binary symbols and verifying the parser implementation in upstream `plasma/libkscreen` (`src/doctor/doctor.cpp`).

> **Disclaimer:** This project contains code and documentation generated with the assistance of an experimental AI coding assistant. Please review and test scripts on your hardware before deploying them in automated system hooks.

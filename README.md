# KDE Additional Power Management Tweaks

A lightweight, non-intrusive power management script designed for KDE Plasma (Wayland) on modern AMD laptops (such as Lenovo IdeaPad/Slim series).

Runs cleanly in user space without requiring `sudo` or root privileges, making it directly usable inside **KDE System Settings → Power Management → Run script**.

---

## What It Optimizes

### 1. Display & GPU Pipeline Optimization (via `kscreen-doctor`)
Leverages hardware and driver-level controls exposed by KWin and `amdgpu`:

| Setting | AC Mode (`ac`) | Battery Mode (`battery`) | Low Battery (`low_battery`) | Power Benefit |
| :--- | :--- | :--- | :--- | :--- |
| **Refresh Rate (All Displays)** | `Max Hz` (at current res) | `Lowest Hz` (at current res) | `Lowest Hz` (at current res) | Cuts GPU scanout & panel timing controller power on multi-rate displays |
| **ABM (Backlight Modulation)** | `0` (Disabled) | `4` (Maximum) | `4` (Maximum) | Reduces panel backlight draw by modulating contrast |
| **Color Power Tradeoff** | `preferAccuracy` | `preferEfficiency` | `preferEfficiency` | Enables direct scanout (MPO planes) & lower-power framebuffer formats |
| **Color Bit Depth (`maxbpc`)** | `automatic` (10/16-bit) | `8` (8-bit) | `8` (8-bit) | Reduces eDP link bandwidth and display engine power |
| **EDR Policy** | `always` | `never` | `never` | Blocks apps from driving peak backlight headroom |
| **Adaptive Sync (`vrrpolicy`)** | `automatic` | `always` | `always` | Allows the panel to drop refresh rate during static/video content |
| **Software Dimming** | `100%` | `100%` | `80%` | Additional software dimming for emergency battery conservation |

### 2. KWin Compositor & Animation Effects (via `qdbus6`)
Disables shader-heavy rendering, spring physics, and multi-frame geometry transforms on battery so window actions become instantaneous with zero continuous GPU redraw cycles:
- **Shaders & Translucency**: `blur`, `translucency`
- **Window Movements & Physics**: `wobblywindows`, `fallapart`
- **Input Tracking**: `touchpoints` (prevents high CPU usage from multi-finger touch tracking overlays)
- **Window State Transitions**: `scale`, `squash` (minimize/maximize transforms)
- **Virtual Desktops & Shell**: `slide`, `slideback`, `slidingpopups`, `slidingnotifications`
*(All unloaded on Battery / Low Battery; restored on AC)*

### 3. KDE Background Watchers / KDED6 Modules (via `qdbus6`)
- **Battery / Low Battery**: Unloads non-essential background polling modules in `kded6` (`smbwatcher`, `remotenotifier`, `freespacenotifier`) to reduce periodic disk/network wakeups.
- **AC**: Reloads all three modules.

### 4. Smart Bluetooth Management (`rfkill` / `bluetoothctl`)
- **Battery / Low Battery**: Checks `bluetoothctl devices Connected`. If **no active devices** are connected (e.g. mouse, headphones), Bluetooth is soft-blocked to stop continuous inquiry/page scanning. If a device **is** connected, Bluetooth remains active uninterrupted.
- **AC**: Bluetooth is automatically unblocked.

### 5. Keyboard Backlight Auto-Off (KDE Solid D-Bus)
- Automatically sets keyboard brightness to `0` on **Battery** and **Low Battery** to eliminate physical LED drain.

### 6. IdeaPad Always-On USB Charging (`ideapad_acpi`)
- **Low Battery**: Shuts off external USB standby port charging (`usb_charging = 0`) to prevent attached dongles, cables, or external devices from draining the remaining emergency reserve.
- **AC / Battery**: Kept enabled (`1`).

### 7. Background Update Timers, Foreground Boosters, PSD & KDE Connect (`systemd --user`)
- **Update Timers (`arch-update.timer`)**: Paused on **Battery** and **Low Battery** to avoid background network probes and package cache refreshes; resumed on **AC**.
- **Browser RAM-to-SSD Hourly Sync (`psd-resync.timer`)**: Stopped on **Low Battery** so Profile-Sync-Daemon keeps browser writes strictly in `tmpfs` RAM without hourly NVMe `rsync` bursts; resumed on **AC** and **Battery**.
- **Foreground CPU/GPU Boosters (`plasma-foreground-booster.service` & `dmemcg-booster-user.service`)**: Stopped on **Low Battery** to prevent aggressive CPU cgroup boost spikes when switching windows; kept active on **AC** and **Battery**.
- **KDE Connect (`app-org.kde.kdeconnect.daemon@autostart.service`)**: Stopped on **Low Battery** to eliminate background LAN broadcasts, clipboard listeners, and Wi-Fi packet wakeups when battery is critical; automatically restarted on **AC** and **Battery**.

### 8. User Cgroup v2 Memory, Swap & Scheduling Tweaks (`background.slice`)
- **Battery / Low Battery**:
  - Sets `cpu.idle = 1` (`SCHED_IDLE`) and `io.prio.class = idle` on `/sys/fs/cgroup/user.slice/.../background.slice` so background services never ramp CPU/Infinity Fabric clocks or wake storage independently.
  - Triggers a one-time `64M` cold-page reclaim (`memory.reclaim`) to compress idle daemon pages into `zstd` ZRAM, and caps `memory.swap.high = 512M` so background services cannot spill past ZRAM onto the NVMe swapfile.
- **AC**: Restores `cpu.idle = 0`, `io.prio.class = no-change`, and `memory.swap.high = max`.

### 9. PipeWire Audio Buffer Quantum (`pw-metadata`)
- **Low Battery**: Forces `clock.force-quantum` to `2048` samples, cutting audio thread CPU wakeups and interrupts by 2x–8x during media playback or calls.
- **AC / Battery**: Reset to `0` (dynamic low-latency buffer scaling).

### 10. System Color Scheme / Dark Mode (`plasma-apply-colorscheme`)
- **Why it matters for ABM**: Adaptive Backlight Modulation analyzes screen content brightness. Dark backgrounds allow ABM to aggressively drop the physical panel backlight without losing detail, yielding maximum power savings.
- **Battery / Low Battery**: Automatically switches Plasma to `BreezeDark` (and triggers the FreeDesktop `prefer-dark` portal). If you were using a light theme on AC, your active scheme is saved to `~/.local/state/kde-power-management/ac-colorscheme`.
- **AC**: Seamlessly restores your original AC color scheme.

### 11. Desktop Notifications (`notify-send`)
- Dispatches formatted KDE Plasma desktop notifications whenever a power state change occurs, summarizing the specific optimizations applied (display refresh rate & ABM, compositor effects, KDED modules, Bluetooth, cgroup priorities, audio buffers, and themes).
- Configured with native icons (`battery-charging`, `battery`, `battery-low`) and appropriate urgency hints.

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

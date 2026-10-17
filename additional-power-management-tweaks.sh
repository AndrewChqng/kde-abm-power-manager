#!/usr/bin/env bash
# additional-power-management-tweaks.sh
# Adjusts display, compositor, hardware, and service power parameters based on power state.
#
# Supports:
#   1. Display & GPU Pipeline (via kscreen-doctor):
#      - Adaptive Backlight Modulation (ABM): 0 on AC, 4 on Battery / Low Battery
#      - Color Power Tradeoff: preferAccuracy on AC, preferEfficiency on Battery / Low Battery
#      - Color Bit Depth (maxbpc): automatic on AC, 8 on Battery / Low Battery
#      - EDR Policy: always on AC, never on Battery / Low Battery
#      - Adaptive Sync / VRR Policy: automatic on AC, always on Battery / Low Battery
#      - Display Dimming: 100% on AC / Battery, 80% on Low Battery
#   2. KWin Compositor Effects (via qdbus6):
#      - blur, translucency, wobblywindows, scale, squash, slide, slideback,
#        slidingpopups, slidingnotifications, fallapart, touchpoints:
#        loaded on AC, unloaded on Battery / Low Battery (cuts continuous CPU/GPU redraw)
#   3. KDE Background Watchers / KDED6 Modules (via qdbus6):
#      - smbwatcher, remotenotifier, freespacenotifier:
#        loaded on AC, unloaded on Battery / Low Battery
#   4. Smart Bluetooth Power Management (rfkill / bluetoothctl):
#      - Unblocked on AC
#      - Soft-blocked on Battery / Low Battery ONLY if no Bluetooth device is currently connected
#   5. Keyboard Backlight (via KDE Solid D-Bus):
#      - Turned off (level 0) on Battery / Low Battery
#   6. Lenovo IdeaPad USB Standby Charging:
#      - Disabled (0) on Low Battery to prevent peripherals/cables from siphoning reserve power
#      - Enabled (1) on AC / Battery
#   7. Background System Update Timers, Boosters & KDE Connect (systemd --user):
#      - arch-update.timer stopped on Battery / Low Battery, started on AC
#      - plasma-foreground-booster.service, dmemcg-booster-user.service &
#        app-org.kde.kdeconnect.daemon@autostart.service stopped on Low Battery,
#        started on AC / Battery
#   8. PipeWire Audio Buffer Quantum (pw-metadata):
#      - Forced to 2048 samples on Low Battery to reduce audio CPU interrupts
#      - Reset to 0 (dynamic low-latency) on AC / Battery
#   9. System Color Scheme / Dark Mode (plasma-apply-colorscheme):
#      - Switches to BreezeDark on Battery / Low Battery to maximize ABM backlight power savings
#      - Saves and restores original color scheme when returning to AC
#
# Usage:
#   additional-power-management-tweaks.sh <ac|battery|low_battery|"low battery"> [output_name]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [output]

Modes:
  ac                        AC power profile:
                              - ABM: 0 (disabled)
                              - Color power tradeoff: preferAccuracy
                              - Max bits per color (maxbpc): automatic
                              - EDR policy: always
                              - VRR policy: automatic
                              - Display dimming: 100%
                              - KWin visual & animation effects: enabled
                              - KDED background watchers: enabled
                              - Bluetooth: unblocked
                              - IdeaPad USB charging: enabled
                              - arch-update.timer: active
                              - Foreground boosters & KDE Connect: active
                              - PipeWire force-quantum: 0 (dynamic)
                              - Color scheme: restored to AC preference

  battery                   Standard battery power profile:
                              - ABM: 4 (maximum power saving)
                              - Color power tradeoff: preferEfficiency
                              - Max bits per color (maxbpc): 8
                              - EDR policy: never
                              - VRR policy: always
                              - Display dimming: 100%
                              - KWin visual & animation effects: disabled (instant rendering)
                              - KDED background watchers: unloaded
                              - Bluetooth: blocked if no device is connected
                              - Keyboard backlight: turned off
                              - arch-update.timer: paused
                              - Foreground boosters & KDE Connect: active
                              - PipeWire force-quantum: 0 (dynamic)
                              - Color scheme: switched to BreezeDark for ABM

  low_battery, "low battery", low-battery, low
                            Aggressive battery saving profile:
                              - All battery optimizations above
                              - Display dimming: 80%
                              - IdeaPad USB standby charging: disabled
                              - Foreground boosters & KDE Connect: stopped
                              - PipeWire force-quantum: 2048 (large power-saving buffer)

Arguments:
  output                    Optional display output name (e.g. eDP-1).
                            If omitted, auto-detects the first connected eDP*
                            panel via kscreen-doctor, falling back to eDP-1.
EOF
}

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

MODE="${1,,}" # normalize to lowercase
OUTPUT="${2:-}"

case "$MODE" in
    ac)
        ABM_LEVEL=0
        COLOR_POWER="preferAccuracy"
        MAX_BPC="automatic"
        EDR_POLICY="always"
        VRR_POLICY="automatic"
        DIMMING=100
        ENABLE_COMPOSITOR_EFFECTS=true
        ENABLE_KDED_WATCHERS=true
        DISABLE_KBD_BACKLIGHT=false
        BLUETOOTH_ACTION="unblock"
        USB_CHARGING=1
        PAUSE_UPDATE_TIMER=false
        PAUSE_FOREGROUND_BOOSTERS=false
        PIPEWIRE_FORCE_QUANTUM=0
        COLOR_SCHEME_MODE="restore"
        ;;
    battery)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        VRR_POLICY="always"
        DIMMING=100
        ENABLE_COMPOSITOR_EFFECTS=false
        ENABLE_KDED_WATCHERS=false
        DISABLE_KBD_BACKLIGHT=true
        BLUETOOTH_ACTION="auto_block"
        USB_CHARGING=1
        PAUSE_UPDATE_TIMER=true
        PAUSE_FOREGROUND_BOOSTERS=false
        PIPEWIRE_FORCE_QUANTUM=0
        COLOR_SCHEME_MODE="dark"
        ;;
    low_battery|"low battery"|low-battery|low)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        VRR_POLICY="always"
        DIMMING=80
        ENABLE_COMPOSITOR_EFFECTS=false
        ENABLE_KDED_WATCHERS=false
        DISABLE_KBD_BACKLIGHT=true
        BLUETOOTH_ACTION="auto_block"
        USB_CHARGING=0
        PAUSE_UPDATE_TIMER=true
        PAUSE_FOREGROUND_BOOSTERS=true
        PIPEWIRE_FORCE_QUANTUM=2048
        COLOR_SCHEME_MODE="dark"
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        echo "Error: Unknown power mode '$1'." >&2
        usage >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------
# Locate D-Bus utility (qdbus6 or qdbus)
# ---------------------------------------------------------
QDBUS_BIN=""
if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS_BIN="qdbus6"
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS_BIN="qdbus"
fi

# ---------------------------------------------------------
# 1. Display & GPU Pipeline Tweaks (kscreen-doctor)
# ---------------------------------------------------------
if command -v kscreen-doctor >/dev/null 2>&1; then
    # Auto-detect internal eDP display if not explicitly provided
    if [[ -z "$OUTPUT" ]]; then
        DETECTED_OUTPUT=$(kscreen-doctor -o 2>/dev/null \
            | sed 's/\x1b\[[0-9;]*m//g' \
            | awk '/^Output:/ { for (i=1; i<=NF; i++) if ($i ~ /^eDP/) { print $i; exit } }' || true)
        OUTPUT="${DETECTED_OUTPUT:-eDP-1}"
    fi

    echo "Applying display power profile on '${OUTPUT}' (mode: ${MODE}):"
    echo "  - ABM level: ${ABM_LEVEL}"
    echo "  - Color power tradeoff: ${COLOR_POWER}"
    echo "  - Max bits per color: ${MAX_BPC}"
    echo "  - EDR policy: ${EDR_POLICY}"
    echo "  - VRR policy: ${VRR_POLICY}"
    echo "  - Dimming: ${DIMMING}%"

    kscreen-doctor \
        "output.${OUTPUT}.abm.${ABM_LEVEL}" \
        "output.${OUTPUT}.colorPowerTradeoff.${COLOR_POWER}" \
        "output.${OUTPUT}.maxbpc.${MAX_BPC}" \
        "output.${OUTPUT}.edrPolicy.${EDR_POLICY}" \
        "output.${OUTPUT}.vrrpolicy.${VRR_POLICY}" \
        "output.${OUTPUT}.dimming.${DIMMING}" || {
            echo "Warning: Some kscreen-doctor parameters could not be applied." >&2
        }
else
    echo "Warning: kscreen-doctor not found, skipping display tweaks." >&2
fi

# ---------------------------------------------------------
# 2. KWin Compositor Effects Tweaks (qdbus)
# ---------------------------------------------------------
if [[ -n "$QDBUS_BIN" ]]; then
    # Shader-heavy and geometry transform animation effects
    HEAVY_EFFECTS=(
        "blur"
        "translucency"
        "wobblywindows"
        "scale"
        "squash"
        "slide"
        "slideback"
        "slidingpopups"
        "slidingnotifications"
        "fallapart"
        "touchpoints"
    )
    if [[ "$ENABLE_COMPOSITOR_EFFECTS" == "true" ]]; then
        echo "Restoring KWin visual & animation effects (${HEAVY_EFFECTS[*]})..."
        for effect in "${HEAVY_EFFECTS[@]}"; do
            "$QDBUS_BIN" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$effect" >/dev/null 2>&1 || true
        done
    else
        echo "Disabling heavy KWin visual & animation effects (${HEAVY_EFFECTS[*]})..."
        for effect in "${HEAVY_EFFECTS[@]}"; do
            "$QDBUS_BIN" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$effect" >/dev/null 2>&1 || true
        done
    fi
fi

# ---------------------------------------------------------
# 3. KDE Background Watchers / KDED Modules (qdbus)
# ---------------------------------------------------------
if [[ -n "$QDBUS_BIN" ]]; then
    KDED_WATCHER_MODULES=(
        "smbwatcher"
        "remotenotifier"
        "freespacenotifier"
    )
    if [[ "$ENABLE_KDED_WATCHERS" == "true" ]]; then
        echo "Restoring KDED background watcher modules (${KDED_WATCHER_MODULES[*]})..."
        for mod in "${KDED_WATCHER_MODULES[@]}"; do
            "$QDBUS_BIN" org.kde.kded6 /kded org.kde.kded6.loadModule "$mod" >/dev/null 2>&1 || true
        done
    else
        echo "Unloading KDED background watcher modules (${KDED_WATCHER_MODULES[*]})..."
        for mod in "${KDED_WATCHER_MODULES[@]}"; do
            "$QDBUS_BIN" org.kde.kded6 /kded org.kde.kded6.unloadModule "$mod" >/dev/null 2>&1 || true
        done
    fi
fi

# ---------------------------------------------------------
# 4. Smart Bluetooth Management (rfkill / bluetoothctl)
# ---------------------------------------------------------
if command -v rfkill >/dev/null 2>&1; then
    if [[ "$BLUETOOTH_ACTION" == "unblock" ]]; then
        echo "Unblocking Bluetooth on AC..."
        rfkill unblock bluetooth 2>/dev/null || true
    elif [[ "$BLUETOOTH_ACTION" == "auto_block" ]]; then
        # Check if any bluetooth devices are currently connected
        HAS_CONNECTED_DEVICE=false
        if command -v bluetoothctl >/dev/null 2>&1; then
            if bluetoothctl devices Connected 2>/dev/null | grep -q "Device"; then
                HAS_CONNECTED_DEVICE=true
            fi
        fi

        if [[ "$HAS_CONNECTED_DEVICE" == "true" ]]; then
            echo "Active Bluetooth device connected; keeping Bluetooth active."
        else
            echo "No active Bluetooth devices connected; soft-blocking Bluetooth to save power..."
            rfkill block bluetooth 2>/dev/null || true
        fi
    fi
fi

# ---------------------------------------------------------
# 5. Keyboard Backlight Auto-Off (KDE Solid D-Bus)
# ---------------------------------------------------------
if [[ "$DISABLE_KBD_BACKLIGHT" == "true" && -n "$QDBUS_BIN" ]]; then
    echo "Turning off keyboard backlight on battery..."
    "$QDBUS_BIN" org.kde.Solid.PowerManagement \
        /org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl \
        org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl.setKeyboardBrightness 0 >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------
# 6. IdeaPad Always-On USB Charging (Low Battery only)
# ---------------------------------------------------------
IDEAPAD_USB_NODE="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/usb_charging"
if [[ -w "$IDEAPAD_USB_NODE" ]]; then
    CURRENT_USB_VAL=$(cat "$IDEAPAD_USB_NODE" 2>/dev/null || true)
    if [[ "$CURRENT_USB_VAL" != "$USB_CHARGING" ]]; then
        echo "Setting IdeaPad USB charging to ${USB_CHARGING}..."
        echo "$USB_CHARGING" > "$IDEAPAD_USB_NODE" 2>/dev/null || true
    fi
fi

# ---------------------------------------------------------
# 7. Background Update Timers, Boosters & KDE Connect (systemd --user)
# ---------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    if [[ "$PAUSE_UPDATE_TIMER" == "true" ]]; then
        if systemctl --user is-active --quiet arch-update.timer 2>/dev/null; then
            echo "Pausing arch-update.timer on battery..."
            systemctl --user stop arch-update.timer 2>/dev/null || true
        fi
    else
        if ! systemctl --user is-active --quiet arch-update.timer 2>/dev/null; then
            echo "Resuming arch-update.timer on AC..."
            systemctl --user start arch-update.timer 2>/dev/null || true
        fi
    fi

    LOW_BATTERY_STOP_SERVICES=(
        "plasma-foreground-booster.service"
        "dmemcg-booster-user.service"
        "app-org.kde.kdeconnect.daemon@autostart.service"
    )
    if [[ "$PAUSE_FOREGROUND_BOOSTERS" == "true" ]]; then
        for svc in "${LOW_BATTERY_STOP_SERVICES[@]}"; do
            if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
                echo "Stopping ${svc} on low battery..."
                systemctl --user stop "$svc" 2>/dev/null || true
            fi
        done
    else
        for svc in "${LOW_BATTERY_STOP_SERVICES[@]}"; do
            if systemctl --user cat "$svc" >/dev/null 2>&1 && ! systemctl --user is-active --quiet "$svc" 2>/dev/null; then
                echo "Starting ${svc}..."
                systemctl --user start "$svc" 2>/dev/null || true
            fi
        done
    fi
fi

# ---------------------------------------------------------
# 8. PipeWire Audio Buffer Quantum (Low Battery only)
# ---------------------------------------------------------
if command -v pw-metadata >/dev/null 2>&1; then
    echo "Setting PipeWire clock.force-quantum to ${PIPEWIRE_FORCE_QUANTUM}..."
    pw-metadata -n settings 0 clock.force-quantum "${PIPEWIRE_FORCE_QUANTUM}" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------
# 9. System Color Scheme / Dark Mode (plasma-apply-colorscheme)
# ---------------------------------------------------------
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    SCHEME_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/kde-power-management/ac-colorscheme"
    CURRENT_SCHEME=""
    if command -v kreadconfig6 >/dev/null 2>&1; then
        CURRENT_SCHEME=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)
    fi

    if [[ "$COLOR_SCHEME_MODE" == "dark" ]]; then
        # If currently not on a dark scheme, save the active scheme to restore on AC
        if [[ "$CURRENT_SCHEME" != "BreezeDark" ]]; then
            mkdir -p "$(dirname "$SCHEME_STATE_FILE")"
            if [[ -n "$CURRENT_SCHEME" ]]; then
                echo "$CURRENT_SCHEME" > "$SCHEME_STATE_FILE"
            fi
            echo "Switching to dark color scheme (BreezeDark) to maximize ABM power savings..."
            plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
        fi
    elif [[ "$COLOR_SCHEME_MODE" == "restore" ]]; then
        # Restore saved AC color scheme if present
        if [[ -f "$SCHEME_STATE_FILE" ]]; then
            SAVED_SCHEME=$(cat "$SCHEME_STATE_FILE" 2>/dev/null || true)
            rm -f "$SCHEME_STATE_FILE"
            if [[ -n "$SAVED_SCHEME" && "$SAVED_SCHEME" != "$CURRENT_SCHEME" ]]; then
                echo "Restoring AC color scheme (${SAVED_SCHEME})..."
                plasma-apply-colorscheme "$SAVED_SCHEME" >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

echo "Power profile '${MODE}' successfully applied."

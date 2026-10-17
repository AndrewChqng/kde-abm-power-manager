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
#      - Display Dimming: 100% on AC / Battery, 80% on Low Battery
#   2. KWin Compositor Effects (via qdbus6):
#      - blur, translucency, wobblywindows, scale, squash, slide, slideback,
#        slidingpopups, slidingnotifications, fallapart, touchpoints:
#        loaded on AC, unloaded on Battery / Low Battery (cuts continuous CPU/GPU redraw)
#   3. Smart Bluetooth Power Management (rfkill / bluetoothctl):
#      - Unblocked on AC
#      - Soft-blocked on Battery / Low Battery ONLY if no Bluetooth device is currently connected
#   4. Keyboard Backlight (via KDE Solid D-Bus):
#      - Turned off (level 0) on Battery / Low Battery
#   5. Lenovo IdeaPad USB Standby Charging:
#      - Disabled (0) on Low Battery to prevent peripherals/cables from siphoning reserve power
#      - Enabled (1) on AC / Battery
#   6. Background System Update Timers (systemd --user):
#      - arch-update.timer stopped on Battery / Low Battery to avoid background network/CPU wakeups
#      - Started on AC
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
                              - Display dimming: 100%
                              - KWin visual & animation effects: enabled
                              - Bluetooth: unblocked
                              - IdeaPad USB charging: enabled
                              - arch-update.timer: active

  battery                   Standard battery power profile:
                              - ABM: 4 (maximum power saving)
                              - Color power tradeoff: preferEfficiency
                              - Max bits per color (maxbpc): 8
                              - EDR policy: never
                              - Display dimming: 100%
                              - KWin visual & animation effects: disabled (instant rendering)
                              - Bluetooth: blocked if no device is connected
                              - Keyboard backlight: turned off
                              - arch-update.timer: paused

  low_battery, "low battery", low-battery, low
                            Aggressive battery saving profile:
                              - All battery optimizations above
                              - Display dimming: 80%
                              - IdeaPad USB standby charging: disabled

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
        DIMMING=100
        ENABLE_COMPOSITOR_EFFECTS=true
        DISABLE_KBD_BACKLIGHT=false
        BLUETOOTH_ACTION="unblock"
        USB_CHARGING=1
        PAUSE_UPDATE_TIMER=false
        ;;
    battery)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        DIMMING=100
        ENABLE_COMPOSITOR_EFFECTS=false
        DISABLE_KBD_BACKLIGHT=true
        BLUETOOTH_ACTION="auto_block"
        USB_CHARGING=1
        PAUSE_UPDATE_TIMER=true
        ;;
    low_battery|"low battery"|low-battery|low)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        DIMMING=80
        ENABLE_COMPOSITOR_EFFECTS=false
        DISABLE_KBD_BACKLIGHT=true
        BLUETOOTH_ACTION="auto_block"
        USB_CHARGING=0
        PAUSE_UPDATE_TIMER=true
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
    echo "  - Dimming: ${DIMMING}%"

    kscreen-doctor \
        "output.${OUTPUT}.abm.${ABM_LEVEL}" \
        "output.${OUTPUT}.colorPowerTradeoff.${COLOR_POWER}" \
        "output.${OUTPUT}.maxbpc.${MAX_BPC}" \
        "output.${OUTPUT}.edrPolicy.${EDR_POLICY}" \
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
# 3. Smart Bluetooth Management (rfkill / bluetoothctl)
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
# 4. Keyboard Backlight Auto-Off (KDE Solid D-Bus)
# ---------------------------------------------------------
if [[ "$DISABLE_KBD_BACKLIGHT" == "true" && -n "$QDBUS_BIN" ]]; then
    echo "Turning off keyboard backlight on battery..."
    "$QDBUS_BIN" org.kde.Solid.PowerManagement \
        /org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl \
        org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl.setKeyboardBrightness 0 >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------
# 5. IdeaPad Always-On USB Charging (Low Battery only)
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
# 6. Background Update Timer Throttling (systemd --user)
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
fi

echo "Power profile '${MODE}' successfully applied."

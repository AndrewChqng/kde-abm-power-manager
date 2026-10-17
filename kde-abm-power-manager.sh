#!/usr/bin/env bash
# kde-abm-power-manager.sh
# Adjusts KDE Display power parameters and KWin Compositor effects based on power state.
#
# Supports:
#   1. Display & GPU Pipeline (via kscreen-doctor):
#      - Adaptive Backlight Modulation (ABM): 0 on AC, 4 on Battery / Low Battery
#      - Color Power Tradeoff: preferAccuracy on AC, preferEfficiency on Battery / Low Battery
#      - Color Bit Depth (maxbpc): automatic on AC, 8 on Battery / Low Battery
#      - EDR Policy: always on AC, never on Battery / Low Battery
#      - Display Dimming: 100% on AC / Battery, 80% on Low Battery
#   2. KWin Compositor Effects (via qdbus6):
#      - blur & translucency effects: loaded on AC, unloaded on Battery / Low Battery
#
# Usage:
#   kde-abm-power-manager.sh <ac|battery|low_battery|"low battery"> [output_name]

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
                              - KWin blur & translucency: enabled

  battery                   Standard battery power profile:
                              - ABM: 4 (maximum power saving)
                              - Color power tradeoff: preferEfficiency
                              - Max bits per color (maxbpc): 8
                              - EDR policy: never
                              - Display dimming: 100%
                              - KWin blur & translucency: disabled

  low_battery, "low battery", low-battery, low
                            Aggressive battery saving profile:
                              - All battery optimizations above
                              - Display dimming: 80%

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
        ;;
    battery)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        DIMMING=100
        ENABLE_COMPOSITOR_EFFECTS=false
        ;;
    low_battery|"low battery"|low-battery|low)
        ABM_LEVEL=4
        COLOR_POWER="preferEfficiency"
        MAX_BPC="8"
        EDR_POLICY="never"
        DIMMING=80
        ENABLE_COMPOSITOR_EFFECTS=false
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
# 2. KWin Compositor Effects Tweaks (qdbus6 / qdbus)
# ---------------------------------------------------------
QDBUS_BIN=""
if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS_BIN="qdbus6"
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS_BIN="qdbus"
fi

if [[ -n "$QDBUS_BIN" ]]; then
    HEAVY_EFFECTS=("blur" "translucency")
    if [[ "$ENABLE_COMPOSITOR_EFFECTS" == "true" ]]; then
        echo "Restoring KWin visual effects (${HEAVY_EFFECTS[*]})..."
        for effect in "${HEAVY_EFFECTS[@]}"; do
            "$QDBUS_BIN" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$effect" >/dev/null 2>&1 || true
        done
    else
        echo "Disabling heavy KWin visual effects (${HEAVY_EFFECTS[*]})..."
        for effect in "${HEAVY_EFFECTS[@]}"; do
            "$QDBUS_BIN" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$effect" >/dev/null 2>&1 || true
        done
    fi
fi

echo "Power profile '${MODE}' successfully applied."

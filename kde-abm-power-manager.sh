#!/usr/bin/env bash
# kde-abm-power-manager.sh
# Adjusts KDE Adaptive Backlight Modulation (ABM) level based on power state.
#
# Usage:
#   kde-abm-power-manager.sh <ac|battery|low_battery|"low battery"> [output_name]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [output]

Modes:
  ac                        Set ABM level to 0 (Disabled)
  battery                   Set ABM level to 4 (Maximum power saving)
  low_battery, "low battery", low-battery, low
                            Set ABM level to 4 (Maximum power saving)

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
        ;;
    battery|low_battery|"low battery"|low-battery|low)
        ABM_LEVEL=4
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

if ! command -v kscreen-doctor >/dev/null 2>&1; then
    echo "Error: kscreen-doctor not found in PATH." >&2
    exit 1
fi

# Auto-detect internal eDP display if not explicitly provided
if [[ -z "$OUTPUT" ]]; then
    # Strip ANSI escape codes from kscreen-doctor -o and match the first eDP output name
    DETECTED_OUTPUT=$(kscreen-doctor -o 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | awk '/^Output:/ { for (i=1; i<=NF; i++) if ($i ~ /^eDP/) { print $i; exit } }' || true)
    OUTPUT="${DETECTED_OUTPUT:-eDP-1}"
fi

echo "Setting Adaptive Backlight Modulation (ABM) on '${OUTPUT}' to level ${ABM_LEVEL} (mode: ${MODE})..."
kscreen-doctor "output.${OUTPUT}.abm.${ABM_LEVEL}"

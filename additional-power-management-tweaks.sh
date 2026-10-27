#!/usr/bin/env bash
# additional-power-management-tweaks.sh
# Adjusts display, compositor, hardware, and service power parameters based on power state.
#
# Supports:
#   1. Display & GPU Pipeline (via kscreen-doctor):
#      - Refresh Rate (all active displays): max for current resolution on AC,
#        lowest for current resolution on Battery / Low Battery
#        (prompts via KDE kdialog popup when >1 display is connected)
#      - Adaptive Backlight Modulation (ABM): 0 on AC, 4 on Battery / Low Battery
#      - Color Power Tradeoff: preferEfficiency across all profiles (bypasses GPU compositor blending for direct scanout/MPO performance)
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
#   7. Background System Update Timers, Boosters, KDE Connect & System Services:
#      - arch-update.timer stopped on Battery / Low Battery, started on AC
#      - psd-resync.timer, plasma-foreground-booster.service, dmemcg-booster-user.service &
#        app-org.kde.kdeconnect.daemon@autostart.service stopped on Low Battery,
#        started on AC / Battery
#      - cups.service, avahi-daemon.service & libvirtd.service paused on Low Battery
#        (via Polkit rule), restored on AC / Battery
#   8. User & Root Cgroup v2 Memory, Swap, Scheduling & THP / Compaction Tweaks:
#      - background.slice cpu.idle=1 (SCHED_IDLE) and io.prio.class=idle on Battery / Low Battery
#      - background.slice memory.swap.high=512M & 64M cold-page ZRAM reclaim on Battery / Low Battery
#      - Root cgroup memory.reclaim (128M on Battery, 256M on Low Battery)
#      - Transparent Huge Pages (THP): always on AC, madvise on Battery / Low Battery
#      - Kernel VM writeback & laptop_mode: 15s / 0 on AC, 60s / 5 on Battery, 90s / 5 + RAM compaction on Low Battery
#   9. PipeWire Audio Buffer Quantum & HDA Codec Power Save:
#      - PipeWire clock.force-quantum: 2048 on Low Battery, 0 (dynamic) on AC / Battery
#      - snd_hda_intel power_save: 0 on AC, 1s auto-suspend on Battery / Low Battery
#  10. System Color Scheme / Dark Mode (plasma-apply-colorscheme):
#      - Switches to BreezeDark on Battery / Low Battery to maximize ABM backlight power savings
#      - Saves and restores original color scheme when returning to AC
#  11. CPU Boost, AMD P-State EPP, SMT, Frequency Cap, ACPI Platform Profile, iGPU DPM & PCIe ASPM:
#      - CPU boost: 1 on AC, 0 on Battery / Low Battery
#      - AMD P-State EPP: balance_performance on AC, balance_power on Battery, power on Low Battery
#      - SMT & CPU Max Freq: SMT on & max freq on AC / Battery, SMT off & 2.0 GHz cap on Low Battery
#      - ACPI platform_profile: balanced on AC, low-power on Battery / Low Battery
#      - AMD Radeon iGPU DPM: auto on AC, low on Battery / Low Battery
#      - PCIe ASPM & PCI Runtime PM: default / on for AC, powersave / auto for Battery, powersupersave / auto for Low Battery
#  12. Desktop Notifications (notify-send):
#      - Dispatches rich KDE notifications detailing the exact power optimizations applied
#
# Usage:
#   additional-power-management-tweaks.sh <ac|battery|low_battery|"low battery"> [output_name]

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [output]

Modes:
  ac                        AC power profile:
                              - Refresh rate (all displays): maximum for current resolution
                              - ABM: 0 (disabled), Color: preferEfficiency, maxbpc: automatic, EDR: always, VRR: automatic, Dimming: 100%
                              - CPU: boost=1, EPP=balance_performance, SMT=on, max frequency=unrestricted
                              - Platform & GPU: ACPI profile=balanced, Radeon iGPU DPM=auto
                              - PCIe ASPM & Runtime PM: policy=default, PCI power/control=on
                              - Audio: HDA power_save=0, PipeWire force-quantum=0 (dynamic)
                              - Kernel VM & THP: writeback=1500cs, laptop_mode=0, THP=always
                              - KWin visual & animation effects: enabled
                              - KDED background watchers: enabled
                              - Bluetooth: unblocked, IdeaPad USB charging: enabled
                              - Timers & Services: arch-update, boosters, KDE Connect, PSD & system services active
                              - background.slice cgroup: normal CPU/IO & swap=max
                              - Color scheme: restored to AC preference

  battery                   Standard battery power profile:
                              - Refresh rate (all displays): lowest for current resolution
                              - ABM: 4, Color: preferEfficiency, maxbpc: 8, EDR: never, VRR: always, Dimming: 100%
                              - CPU: boost=0, EPP=balance_power, SMT=on, max frequency=unrestricted
                              - Platform & GPU: ACPI profile=low-power, Radeon iGPU DPM=low
                              - PCIe ASPM & Runtime PM: policy=powersave, PCI/NVMe/USB power/control=auto
                              - Audio: HDA power_save=1, PipeWire force-quantum=0 (dynamic)
                              - Kernel VM & THP: writeback=6000cs (60s), laptop_mode=5, THP=madvise, 128M global ZRAM reclaim
                              - KWin visual & animation effects: disabled (instant rendering)
                              - KDED background watchers: unloaded
                              - Bluetooth: blocked if no device is connected, Keyboard backlight: off
                              - Timers & Services: arch-update paused; boosters, KDE Connect & PSD active
                              - background.slice cgroup: SCHED_IDLE CPU/IO, 512M swap cap & 64M ZRAM reclaim
                              - Color scheme: switched to BreezeDark for ABM

  low_battery, "low battery", low-battery, low
                            Aggressive battery saving profile:
                              - All battery optimizations above
                              - Display dimming: 80%
                              - CPU: boost=0, EPP=power, SMT=off, max frequency capped at 2.0 GHz
                              - PCIe ASPM: policy=powersupersave
                              - Kernel VM: writeback=9000cs (90s), 256M global ZRAM reclaim & physical RAM compaction
                              - IdeaPad USB standby charging: disabled
                              - User & System Services: boosters, KDE Connect, PSD, CUPS, Avahi & Libvirt stopped
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
        REFRESH_TARGET="max"
        ABM_LEVEL=0
        COLOR_POWER="preferEfficiency"
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
        PAUSE_SYSTEM_SERVICES=false
        BG_CPU_IDLE=0
        BG_IO_PRIO="no-change"
        BG_SWAP_HIGH="max"
        BG_RECLAIM=""
        ROOT_CGROUP_RECLAIM=""
        THP_ENABLED="always"
        THP_DEFRAG="defer+madvise"
        VM_WRITEBACK_CENTISECS=1500
        VM_LAPTOP_MODE=0
        COMPACT_MEMORY=false
        PIPEWIRE_FORCE_QUANTUM=0
        AUDIO_POWER_SAVE=0
        COLOR_SCHEME_MODE="restore"
        CPU_BOOST=1
        CPU_EPP="balance_performance"
        CPU_SMT="on"
        CPU_MAX_FREQ_KHZ="max"
        PLATFORM_PROFILE="balanced"
        GPU_DPM_LEVEL="auto"
        PCIE_ASPM_POLICY="default"
        PCI_RUNTIME_PM="on"
        ;;
    battery)
        REFRESH_TARGET="min"
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
        PAUSE_SYSTEM_SERVICES=false
        BG_CPU_IDLE=1
        BG_IO_PRIO="idle"
        BG_SWAP_HIGH="512M"
        BG_RECLAIM="64M"
        ROOT_CGROUP_RECLAIM="128M"
        THP_ENABLED="madvise"
        THP_DEFRAG="madvise"
        VM_WRITEBACK_CENTISECS=6000
        VM_LAPTOP_MODE=5
        COMPACT_MEMORY=false
        PIPEWIRE_FORCE_QUANTUM=0
        AUDIO_POWER_SAVE=1
        COLOR_SCHEME_MODE="dark"
        CPU_BOOST=0
        CPU_EPP="balance_power"
        CPU_SMT="on"
        CPU_MAX_FREQ_KHZ="max"
        PLATFORM_PROFILE="low-power"
        GPU_DPM_LEVEL="low"
        PCIE_ASPM_POLICY="powersave"
        PCI_RUNTIME_PM="auto"
        ;;
    low_battery|"low battery"|low-battery|low)
        REFRESH_TARGET="min"
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
        PAUSE_SYSTEM_SERVICES=true
        BG_CPU_IDLE=1
        BG_IO_PRIO="idle"
        BG_SWAP_HIGH="512M"
        BG_RECLAIM="64M"
        ROOT_CGROUP_RECLAIM="256M"
        THP_ENABLED="madvise"
        THP_DEFRAG="madvise"
        VM_WRITEBACK_CENTISECS=9000
        VM_LAPTOP_MODE=5
        COMPACT_MEMORY=true
        PIPEWIRE_FORCE_QUANTUM=2048
        AUDIO_POWER_SAVE=1
        COLOR_SCHEME_MODE="dark"
        CPU_BOOST=0
        CPU_EPP="power"
        CPU_SMT="off"
        CPU_MAX_FREQ_KHZ="2000000"
        PLATFORM_PROFILE="low-power"
        GPU_DPM_LEVEL="low"
        PCIE_ASPM_POLICY="powersupersave"
        PCI_RUNTIME_PM="auto"
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

# Track applied power optimizations for KDE desktop notification
NOTIFY_CHANGES=()

# ---------------------------------------------------------
# 1. Display & GPU Pipeline Tweaks (kscreen-doctor)
# ---------------------------------------------------------
if command -v kscreen-doctor >/dev/null 2>&1; then
    EXPLICIT_OUTPUT="$OUTPUT"
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

    KSCREEN_ARGS=(
        "output.${OUTPUT}.abm.${ABM_LEVEL}"
        "output.${OUTPUT}.colorPowerTradeoff.${COLOR_POWER}"
        "output.${OUTPUT}.maxbpc.${MAX_BPC}"
        "output.${OUTPUT}.edrPolicy.${EDR_POLICY}"
        "output.${OUTPUT}.vrrpolicy.${VRR_POLICY}"
        "output.${OUTPUT}.dimming.${DIMMING}"
    )

    # Select max (AC) or min (Battery/Low Battery) refresh rate per active display
    # while preserving each display's current resolution.
    REFRESH_STATUS_NOTE="${REFRESH_TARGET} Hz"
    if command -v jq >/dev/null 2>&1; then
        mapfile -t DISPLAY_MODE_LINES < <(
            kscreen-doctor -j 2>/dev/null | jq -r --arg target "$REFRESH_TARGET" '
                .outputs[]
                | select(.connected == true and .enabled == true and .currentModeId != null)
                | . as $out
                | ($out.modes[] | select(.id == $out.currentModeId)) as $cur
                | ($out.modes | map(select(.size.width == $cur.size.width and .size.height == $cur.size.height))) as $same_res
                | (if $target == "max" then ($same_res | max_by(.refreshRate)) else ($same_res | min_by(.refreshRate)) end) as $chosen
                | "\($out.name)\t\($cur.size.width)x\($cur.size.height)\t\($chosen.id)\t\($chosen.refreshRate)\t\($cur.id)\t\($cur.refreshRate)"
            ' || true
        )

        ACTIVE_DISPLAY_COUNT=0
        HAS_REFRESH_CHANGE=false
        PROMPT_SUMMARY=""
        for line in "${DISPLAY_MODE_LINES[@]}"; do
            [[ -z "$line" ]] && continue
            IFS=$'\t' read -r DISP_NAME DISP_RES MODE_ID MODE_HZ CUR_MODE_ID CUR_HZ <<< "$line"
            [[ -z "$DISP_NAME" || -z "$MODE_ID" ]] && continue
            if [[ -n "$EXPLICIT_OUTPUT" && "$DISP_NAME" != "$EXPLICIT_OUTPUT" ]]; then
                continue
            fi
            ((ACTIVE_DISPLAY_COUNT += 1))
            if [[ "$MODE_ID" != "$CUR_MODE_ID" ]]; then
                HAS_REFRESH_CHANGE=true
            fi
            PROMPT_SUMMARY+="$(printf "• %s (%s): %.2f Hz → %.2f Hz\n" "$DISP_NAME" "$DISP_RES" "$CUR_HZ" "$MODE_HZ")"
        done

        APPLY_REFRESH_RATE=true
        if (( ACTIVE_DISPLAY_COUNT > 1 )) && [[ "$HAS_REFRESH_CHANGE" == "true" ]]; then
            PROMPT_MSG=$(printf "Multiple displays detected (%d connected).\nChange display refresh rates to %s for '%s' mode?\n\n%s" \
                "$ACTIVE_DISPLAY_COUNT" "$REFRESH_TARGET" "$MODE" "$PROMPT_SUMMARY")
            if command -v kdialog >/dev/null 2>&1; then
                if ! kdialog --title "KDE Power Management" --icon "video-display" --yesno "$PROMPT_MSG" 2>/dev/null; then
                    APPLY_REFRESH_RATE=false
                fi
            elif command -v zenity >/dev/null 2>&1; then
                if ! zenity --question --title="KDE Power Management" --text="$PROMPT_MSG" 2>/dev/null; then
                    APPLY_REFRESH_RATE=false
                fi
            fi
        fi

        if [[ "$APPLY_REFRESH_RATE" == "true" ]]; then
            for line in "${DISPLAY_MODE_LINES[@]}"; do
                [[ -z "$line" ]] && continue
                IFS=$'\t' read -r DISP_NAME DISP_RES MODE_ID MODE_HZ CUR_MODE_ID CUR_HZ <<< "$line"
                [[ -z "$DISP_NAME" || -z "$MODE_ID" ]] && continue
                if [[ -n "$EXPLICIT_OUTPUT" && "$DISP_NAME" != "$EXPLICIT_OUTPUT" ]]; then
                    continue
                fi
                printf "  - Refresh rate (%s @ %s): %s (%.2f Hz, mode %s)\n" \
                    "$DISP_NAME" "$DISP_RES" "$REFRESH_TARGET" "$MODE_HZ" "$MODE_ID"
                KSCREEN_ARGS+=("output.${DISP_NAME}.mode.${MODE_ID}")
            done
        else
            echo "  - Refresh rate change skipped by user (multiple displays connected)."
            REFRESH_STATUS_NOTE="Hz kept"
        fi
    fi

    NOTIFY_CHANGES+=("Display: ${REFRESH_STATUS_NOTE}, ABM ${ABM_LEVEL}, VRR ${VRR_POLICY}, ${DIMMING}% dimming")

    kscreen-doctor "${KSCREEN_ARGS[@]}" || {
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
        NOTIFY_CHANGES+=("KWin: Animations & compositor effects enabled")
        for effect in "${HEAVY_EFFECTS[@]}"; do
            "$QDBUS_BIN" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$effect" >/dev/null 2>&1 || true
        done
    else
        echo "Disabling heavy KWin visual & animation effects (${HEAVY_EFFECTS[*]})..."
        NOTIFY_CHANGES+=("KWin: Heavy animations & effects disabled")
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
        NOTIFY_CHANGES+=("KDED: Background watchers loaded")
        for mod in "${KDED_WATCHER_MODULES[@]}"; do
            "$QDBUS_BIN" org.kde.kded6 /kded org.kde.kded6.loadModule "$mod" >/dev/null 2>&1 || true
        done
    else
        echo "Unloading KDED background watcher modules (${KDED_WATCHER_MODULES[*]})..."
        NOTIFY_CHANGES+=("KDED: Background watchers unloaded")
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
        NOTIFY_CHANGES+=("Bluetooth: Unblocked")
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
            NOTIFY_CHANGES+=("Bluetooth: Kept active (device connected)")
        else
            echo "No active Bluetooth devices connected; soft-blocking Bluetooth to save power..."
            NOTIFY_CHANGES+=("Bluetooth: Soft-blocked (no devices)")
            rfkill block bluetooth 2>/dev/null || true
        fi
    fi
fi

# ---------------------------------------------------------
# 5. Keyboard Backlight Auto-Off (KDE Solid D-Bus)
# ---------------------------------------------------------
if [[ "$DISABLE_KBD_BACKLIGHT" == "true" && -n "$QDBUS_BIN" ]]; then
    echo "Turning off keyboard backlight on battery..."
    NOTIFY_CHANGES+=("Keyboard Backlight: Turned off")
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
    if [[ "$USB_CHARGING" == "0" ]]; then
        NOTIFY_CHANGES+=("IdeaPad USB: Standby charging disabled")
    elif [[ "$MODE" == "ac" ]]; then
        NOTIFY_CHANGES+=("IdeaPad USB: Standby charging enabled")
    fi
fi

# ---------------------------------------------------------
# 7. Background Update Timers, Boosters, KDE Connect & System Daemons
# ---------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    if [[ "$PAUSE_UPDATE_TIMER" == "true" ]]; then
        if systemctl --user is-active --quiet arch-update.timer 2>/dev/null; then
            echo "Pausing arch-update.timer on battery..."
            systemctl --user stop arch-update.timer 2>/dev/null || true
        fi
        NOTIFY_CHANGES+=("Update Timer: arch-update paused")
    else
        if ! systemctl --user is-active --quiet arch-update.timer 2>/dev/null; then
            echo "Resuming arch-update.timer on AC..."
            systemctl --user start arch-update.timer 2>/dev/null || true
        fi
        NOTIFY_CHANGES+=("Update Timer: arch-update active")
    fi

    LOW_BATTERY_STOP_SERVICES=(
        "psd-resync.timer"
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
        NOTIFY_CHANGES+=("User Services: Boosters, KDE Connect & PSD paused")
    else
        for svc in "${LOW_BATTERY_STOP_SERVICES[@]}"; do
            if systemctl --user cat "$svc" >/dev/null 2>&1 && ! systemctl --user is-active --quiet "$svc" 2>/dev/null; then
                echo "Starting ${svc}..."
                systemctl --user start "$svc" 2>/dev/null || true
            fi
        done
        if [[ "$MODE" == "ac" ]]; then
            NOTIFY_CHANGES+=("User Services: Boosters, KDE Connect & PSD active")
        fi
    fi

    # System-level non-essential daemons (authorized passwordlessly via Polkit rule)
    SYS_SERVICES_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/kde-power-management/active-system-services"
    LOW_BATTERY_SYS_SERVICES=(
        "cups.service"
        "avahi-daemon.service"
        "libvirtd.service"
    )
    if [[ "$PAUSE_SYSTEM_SERVICES" == "true" ]]; then
        mkdir -p "$(dirname "$SYS_SERVICES_STATE_FILE")"
        : > "$SYS_SERVICES_STATE_FILE"
        for sys_svc in "${LOW_BATTERY_SYS_SERVICES[@]}"; do
            if systemctl is-active --quiet "$sys_svc" 2>/dev/null; then
                echo "$sys_svc" >> "$SYS_SERVICES_STATE_FILE"
                echo "Stopping system service ${sys_svc} on low battery..."
                systemctl --no-ask-password stop "$sys_svc" 2>/dev/null || true
            fi
        done
        NOTIFY_CHANGES+=("System Daemons: CUPS, Avahi & Libvirt paused")
    else
        if [[ -f "$SYS_SERVICES_STATE_FILE" ]]; then
            while IFS= read -r sys_svc; do
                [[ -z "$sys_svc" ]] && continue
                if ! systemctl is-active --quiet "$sys_svc" 2>/dev/null; then
                    echo "Restoring system service ${sys_svc}..."
                    systemctl --no-ask-password start "$sys_svc" 2>/dev/null || true
                fi
            done < "$SYS_SERVICES_STATE_FILE"
            rm -f "$SYS_SERVICES_STATE_FILE"
        fi
    fi
fi

# ---------------------------------------------------------
# 8. User & Root Cgroup v2 Memory, Swap, THP & Kernel VM Tweaks
# ---------------------------------------------------------
USER_BG_SLICE="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/background.slice"
if [[ -d "$USER_BG_SLICE" ]]; then
    echo "Applying background.slice cgroup v2 power tweaks (cpu.idle=${BG_CPU_IDLE}, io.prio=${BG_IO_PRIO}, swap.high=${BG_SWAP_HIGH})..."
    [[ -w "$USER_BG_SLICE/cpu.idle" ]] && echo "$BG_CPU_IDLE" > "$USER_BG_SLICE/cpu.idle" 2>/dev/null || true
    [[ -w "$USER_BG_SLICE/io.prio.class" ]] && echo "$BG_IO_PRIO" > "$USER_BG_SLICE/io.prio.class" 2>/dev/null || true
    [[ -w "$USER_BG_SLICE/memory.swap.high" ]] && echo "$BG_SWAP_HIGH" > "$USER_BG_SLICE/memory.swap.high" 2>/dev/null || true
    if [[ -n "$BG_RECLAIM" && -w "$USER_BG_SLICE/memory.reclaim" ]]; then
        echo "Reclaiming ${BG_RECLAIM} of cold pages from background.slice into ZRAM..."
        echo "$BG_RECLAIM" > "$USER_BG_SLICE/memory.reclaim" 2>/dev/null || true
    fi
fi

# Root Cgroup v2 Global Cold-Page Reclaim (writable via udev rule)
if [[ -n "$ROOT_CGROUP_RECLAIM" && -w /sys/fs/cgroup/memory.reclaim ]]; then
    echo "Reclaiming ${ROOT_CGROUP_RECLAIM} of cold pages across root cgroup into ZRAM..."
    echo "$ROOT_CGROUP_RECLAIM" > /sys/fs/cgroup/memory.reclaim 2>/dev/null || true
fi

# Transparent Huge Pages (THP) mode & defrag (writable via udev rule)
if [[ -w /sys/kernel/mm/transparent_hugepage/enabled ]]; then
    echo "Setting Transparent Huge Pages (THP) to ${THP_ENABLED} (defrag=${THP_DEFRAG})..."
    echo "$THP_ENABLED" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
fi
if [[ -w /sys/kernel/mm/transparent_hugepage/defrag ]]; then
    echo "$THP_DEFRAG" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
fi

# Kernel VM Writeback, Laptop Mode & SMT Helper (via Polkit-authorized systemd unit or direct procfs)
VM_HELPER_PROFILE="ac"
[[ "$MODE" == "battery" ]] && VM_HELPER_PROFILE="battery"
[[ "$MODE" != "ac" && "$MODE" != "battery" ]] && VM_HELPER_PROFILE="low_battery"

if command -v systemctl >/dev/null 2>&1 && systemctl cat "kde-power-vm-tune@${VM_HELPER_PROFILE}.service" >/dev/null 2>&1; then
    echo "Applying kernel VM writeback (${VM_WRITEBACK_CENTISECS}cs), laptop_mode (${VM_LAPTOP_MODE}) & SMT (${CPU_SMT})..."
    systemctl --no-ask-password start "kde-power-vm-tune@${VM_HELPER_PROFILE}.service" 2>/dev/null || true
else
    [[ -w /proc/sys/vm/dirty_writeback_centisecs ]] && echo "$VM_WRITEBACK_CENTISECS" > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || true
    [[ -w /proc/sys/vm/laptop_mode ]] && echo "$VM_LAPTOP_MODE" > /proc/sys/vm/laptop_mode 2>/dev/null || true
    if [[ "$COMPACT_MEMORY" == "true" && -w /proc/sys/vm/compact_memory ]]; then
        echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
    fi
fi

if [[ "$BG_CPU_IDLE" == "1" ]]; then
    NOTIFY_CHANGES+=("Memory & VM: THP=${THP_ENABLED}, writeback=$((VM_WRITEBACK_CENTISECS / 100))s, ZRAM reclaim (${ROOT_CGROUP_RECLAIM})")
elif [[ "$MODE" == "ac" ]]; then
    NOTIFY_CHANGES+=("Memory & VM: THP=${THP_ENABLED}, writeback=15s, normal cgroups")
fi

# ---------------------------------------------------------
# 9. PipeWire Buffer Quantum & HDA Audio Codec Power Save
# ---------------------------------------------------------
if command -v pw-metadata >/dev/null 2>&1; then
    echo "Setting PipeWire clock.force-quantum to ${PIPEWIRE_FORCE_QUANTUM}..."
    pw-metadata -n settings 0 clock.force-quantum "${PIPEWIRE_FORCE_QUANTUM}" >/dev/null 2>&1 || true
fi

HDA_POWER_SAVE_NODE="/sys/module/snd_hda_intel/parameters/power_save"
if [[ -w "$HDA_POWER_SAVE_NODE" ]]; then
    echo "Setting snd_hda_intel power_save to ${AUDIO_POWER_SAVE}..."
    echo "$AUDIO_POWER_SAVE" > "$HDA_POWER_SAVE_NODE" 2>/dev/null || true
fi

if [[ "$PIPEWIRE_FORCE_QUANTUM" -gt 0 ]]; then
    NOTIFY_CHANGES+=("Audio: PipeWire ${PIPEWIRE_FORCE_QUANTUM} quantum, HDA power_save=${AUDIO_POWER_SAVE}")
elif [[ "$AUDIO_POWER_SAVE" == "1" ]]; then
    NOTIFY_CHANGES+=("Audio: HDA codec 1s power-save active")
elif [[ "$MODE" == "ac" ]]; then
    NOTIFY_CHANGES+=("Audio: Low-latency PipeWire & HDA always-on")
fi

# ---------------------------------------------------------
# 10. System Color Scheme / Dark Mode (plasma-apply-colorscheme)
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
            NOTIFY_CHANGES+=("Theme: Switched to BreezeDark for ABM")
        else
            NOTIFY_CHANGES+=("Theme: BreezeDark active")
        fi
    elif [[ "$COLOR_SCHEME_MODE" == "restore" ]]; then
        # Restore saved AC color scheme if present
        if [[ -f "$SCHEME_STATE_FILE" ]]; then
            SAVED_SCHEME=$(cat "$SCHEME_STATE_FILE" 2>/dev/null || true)
            rm -f "$SCHEME_STATE_FILE"
            if [[ -n "$SAVED_SCHEME" && "$SAVED_SCHEME" != "$CURRENT_SCHEME" ]]; then
                echo "Restoring AC color scheme (${SAVED_SCHEME})..."
                plasma-apply-colorscheme "$SAVED_SCHEME" >/dev/null 2>&1 || true
                NOTIFY_CHANGES+=("Theme: Restored AC theme (${SAVED_SCHEME})")
            fi
        fi
    fi
fi

# ---------------------------------------------------------
# 11. CPU Boost, AMD P-State EPP, SMT, ACPI Profile, GPU DPM & PCIe ASPM
# ---------------------------------------------------------
# 11a. SMT Control (if writable directly via udev rule)
if [[ -w /sys/devices/system/cpu/smt/control ]]; then
    CURRENT_SMT=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || true)
    if [[ "$CURRENT_SMT" != "$CPU_SMT" ]]; then
        echo "Setting CPU SMT control to ${CPU_SMT}..."
        echo "$CPU_SMT" > /sys/devices/system/cpu/smt/control 2>/dev/null || true
    fi
fi

# 11b. CPU Core Performance Boost
if [[ -w /sys/devices/system/cpu/cpufreq/boost ]]; then
    echo "Setting CPU boost to ${CPU_BOOST}..."
    echo "$CPU_BOOST" > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
fi

# 11c. AMD P-State Energy Performance Preference (EPP) & Frequency Cap
HW_MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/amd_pstate_max_freq 2>/dev/null \
    || cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null \
    || echo "4547946")
TARGET_FREQ_KHZ="$HW_MAX_FREQ"
if [[ "$CPU_MAX_FREQ_KHZ" != "max" ]]; then
    TARGET_FREQ_KHZ="$CPU_MAX_FREQ_KHZ"
fi

echo "Setting CPU EPP=${CPU_EPP} and scaling_max_freq=${TARGET_FREQ_KHZ} kHz..."
for cpufreq_dir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [[ ! -d "$cpufreq_dir" ]] && continue
    [[ -w "$cpufreq_dir/energy_performance_preference" ]] && echo "$CPU_EPP" > "$cpufreq_dir/energy_performance_preference" 2>/dev/null || true
    [[ -w "$cpufreq_dir/scaling_max_freq" ]] && echo "$TARGET_FREQ_KHZ" > "$cpufreq_dir/scaling_max_freq" 2>/dev/null || true
done

if [[ "$CPU_MAX_FREQ_KHZ" == "max" ]]; then
    NOTIFY_CHANGES+=("CPU: boost=${CPU_BOOST}, EPP=${CPU_EPP}, SMT=${CPU_SMT}")
else
    NOTIFY_CHANGES+=("CPU: boost=${CPU_BOOST}, EPP=${CPU_EPP}, SMT=${CPU_SMT}, cap=$((TARGET_FREQ_KHZ / 1000))MHz")
fi

# 11d. ACPI Platform Profile
if [[ -w /sys/firmware/acpi/platform_profile ]]; then
    echo "Setting ACPI platform_profile to ${PLATFORM_PROFILE}..."
    echo "$PLATFORM_PROFILE" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
fi

# 11e. AMD Radeon iGPU Dynamic Power Management (DPM)
for dpm_node in /sys/class/drm/card[0-9]*/device/power_dpm_force_performance_level; do
    if [[ -w "$dpm_node" ]]; then
        echo "Setting Radeon iGPU DPM (${dpm_node}) to ${GPU_DPM_LEVEL}..."
        echo "$GPU_DPM_LEVEL" > "$dpm_node" 2>/dev/null || true
    fi
done

# 11f. PCIe ASPM Policy & PCI / NVMe / USB Runtime PM
if [[ -w /sys/module/pcie_aspm/parameters/policy ]]; then
    echo "Setting PCIe ASPM policy to ${PCIE_ASPM_POLICY}..."
    echo "$PCIE_ASPM_POLICY" > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
fi

echo "Setting PCI runtime PM power/control to ${PCI_RUNTIME_PM}..."
for pci_pm in /sys/bus/pci/devices/*/power/control; do
    [[ -w "$pci_pm" ]] && echo "$PCI_RUNTIME_PM" > "$pci_pm" 2>/dev/null || true
done

if [[ "$PCI_RUNTIME_PM" == "auto" ]]; then
    for dev_pm in /sys/class/nvme/nvme*/power/control /sys/bus/usb/devices/*/power/control; do
        [[ -w "$dev_pm" ]] && echo "auto" > "$dev_pm" 2>/dev/null || true
    done
fi

NOTIFY_CHANGES+=("Hardware: ACPI=${PLATFORM_PROFILE}, GPU DPM=${GPU_DPM_LEVEL}, ASPM=${PCIE_ASPM_POLICY}, PCI PM=${PCI_RUNTIME_PM}")

# ---------------------------------------------------------
# 12. KDE Desktop Notification (notify-send)
# ---------------------------------------------------------
if command -v notify-send >/dev/null 2>&1; then
    case "$MODE" in
        ac)
            NOTIFY_TITLE="KDE Power Profile: AC"
            NOTIFY_ICON="battery-charging"
            NOTIFY_URGENCY="low"
            ;;
        battery)
            NOTIFY_TITLE="KDE Power Profile: Battery"
            NOTIFY_ICON="battery"
            NOTIFY_URGENCY="normal"
            ;;
        low_battery|"low battery"|low-battery|low)
            NOTIFY_TITLE="KDE Power Profile: Low Battery"
            NOTIFY_ICON="battery-low"
            NOTIFY_URGENCY="critical"
            ;;
    esac

    NOTIFY_BODY=""
    for item in "${NOTIFY_CHANGES[@]}"; do
        if [[ -z "$NOTIFY_BODY" ]]; then
            NOTIFY_BODY="• ${item}"
        else
            NOTIFY_BODY="${NOTIFY_BODY}
• ${item}"
        fi
    done

    notify-send \
        --app-name="KDE Power Management" \
        --icon="$NOTIFY_ICON" \
        --urgency="$NOTIFY_URGENCY" \
        --hint=string:desktop-entry:org.kde.powerdevil \
        "$NOTIFY_TITLE" \
        "$NOTIFY_BODY" >/dev/null 2>&1 || true
fi

echo "Power profile '${MODE}' successfully applied."

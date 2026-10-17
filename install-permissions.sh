#!/usr/bin/env bash
# install-permissions.sh
# Installs udev, tmpfiles.d, polkit, and systemd helper rules for KDE Plasma
# power management and immediately triggers them so permissions apply without rebooting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Elevating privileges to install udev, tmpfiles, polkit & systemd rules..."
    exec pkexec "$0" "$@"
fi

echo "Installing /etc/udev/rules.d/99-kde-abm-power-manager.rules..."
install -m 0644 "${SCRIPT_DIR}/99-kde-abm-power-manager.rules" /etc/udev/rules.d/99-kde-abm-power-manager.rules

echo "Installing /etc/tmpfiles.d/kde-abm-power-manager.conf..."
install -m 0644 "${SCRIPT_DIR}/kde-abm-power-manager-tmpfiles.conf" /etc/tmpfiles.d/kde-abm-power-manager.conf
systemd-tmpfiles --create /etc/tmpfiles.d/kde-abm-power-manager.conf

echo "Installing /etc/systemd/system/kde-power-vm-tune@.service..."
install -m 0644 "${SCRIPT_DIR}/kde-power-vm-tune@.service" /etc/systemd/system/kde-power-vm-tune@.service
systemctl daemon-reload

if [[ -d /etc/polkit-1/rules.d ]]; then
    echo "Installing /etc/polkit-1/rules.d/50-kde-abm-power-manager.rules..."
    install -m 0644 "${SCRIPT_DIR}/50-kde-abm-power-manager.rules" /etc/polkit-1/rules.d/50-kde-abm-power-manager.rules
fi

echo "Reloading and triggering udev rules..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=cpu \
                --subsystem-match=drm \
                --subsystem-match=pci \
                --subsystem-match=nvme \
                --subsystem-match=usb \
                --subsystem-match=sound \
                --subsystem-match=platform \
                --subsystem-match=power_supply

echo "Done! All kernel and hardware power management nodes are now accessible to the 'wheel' group."

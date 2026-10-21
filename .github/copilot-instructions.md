# Copilot instructions

## Repository scope

This repository is a Bash-based KDE Plasma 6 / Wayland power-management suite for Linux laptops. It is intentionally hardware-aware but best-effort: the main script checks whether commands and sysfs nodes exist, so missing AMD, Lenovo, PipeWire, Bluetooth, or KDE interfaces should generally be skipped rather than treated as fatal.

## Build, test, and lint

There is no build system, package manifest, automated test suite, or configured linter. The executable scripts are the deliverable.

Use these checks after changing shell code:

```bash
# Syntax-check either script without executing its system changes
bash -n additional-power-management-tweaks.sh
bash -n install-permissions.sh
```

The closest thing to a single-profile smoke test is to run one profile manually from a live KDE session. These commands change desktop and hardware power state, so restore the normal state afterward:

```bash
./additional-power-management-tweaks.sh battery
./additional-power-management-tweaks.sh low_battery
./additional-power-management-tweaks.sh ac
```

An optional display output can be supplied for display testing, for example:

```bash
./additional-power-management-tweaks.sh battery eDP-1
```

The installer is a privileged, one-time integration step rather than a test:

```bash
chmod +x additional-power-management-tweaks.sh install-permissions.sh
./install-permissions.sh
```

## Architecture

- `additional-power-management-tweaks.sh` is the runtime entry point called by KDE PowerDevil. It normalizes the requested mode, assigns a complete set of per-profile values, then applies independent subsystems in order: display/KScreen, KWin effects and KDED modules over D-Bus, Bluetooth and keyboard backlight, Lenovo USB charging, user/system services, cgroup/THP/VM settings, PipeWire/HDA, color scheme, CPU/GPU/PCI power controls, and notifications.
- The profile case statement near the top of the runtime script is the source of truth for AC, battery, and low-battery policy. Keep any new power setting defined there for every profile before using it in the application sections.
- `install-permissions.sh` installs the repository’s integration files into `/etc`, reloads systemd, creates tmpfiles, reloads/triggers udev, and uses `pkexec` to elevate when needed. It is designed to let a member of `wheel` run the PowerDevil script without recurring password prompts.
- `99-kde-abm-power-manager.rules` assigns `wheel` group ownership and write permissions to relevant CPU, DRM, PCI/NVMe/USB, sound, Lenovo platform, VM, THP, and cgroup interfaces when devices or power supplies appear.
- `kde-abm-power-manager-tmpfiles.conf` applies persistent boot-time permissions to interfaces that are not reliably handled by device udev events.
- `kde-power-vm-tune@.service` is the Polkit-authorized systemd oneshot fallback/helper for `/proc/sys/vm/*` settings and SMT control, which cannot be handled uniformly by ordinary sysfs permissions.
- `50-kde-abm-power-manager.rules` restricts passwordless systemd unit management to the specific helper profiles and non-essential `cups`, `avahi-daemon`, and `libvirtd` services.

PowerDevil can invoke the runtime entry point with `ac`, `battery`, or `low_battery`; the script also accepts `low battery`, `low-battery`, and `low`. It stores temporary restoration state under `${XDG_STATE_HOME:-$HOME/.local/state}/kde-power-management/`, including the saved AC color scheme and system services stopped for low battery.

## Repository-specific conventions

- Keep scripts Bash and preserve `set -euo pipefail`. Use arrays and quoted expansions for command arguments; do not replace guarded sysfs writes with unguarded writes.
- Treat hardware and desktop capabilities as optional. Follow the existing pattern of `command -v`, `[[ -w ... ]]`, `[[ -d ... ]]`, or readable-node checks before invoking a subsystem. A laptop without a particular node should still complete the other profile changes.
- Profile application is intentionally idempotent and reversible: AC restores effects, services, Bluetooth, USB charging, VM settings, and a previously saved color scheme; low battery records active system services before stopping them. Preserve those transitions and state-file paths when changing behavior.
- Most individual hardware/D-Bus/systemd operations are best-effort and use `|| true` because support varies by kernel, desktop session, and hardware. Do not turn optional capability failures into a full-profile failure without a deliberate UX reason.
- Keep user-session operations in the normal desktop-user script. Root-only kernel/procfs operations should go through the installed helper service or existing permission rules, not ad hoc `sudo` calls.
- When adding a control, update the profile variables, the corresponding application section, and the usage/help text (and README tables or installation instructions when the user-visible contract changes). Keep notification output aligned with the settings actually attempted.
- Preserve the distinction between user services (`systemctl --user`) and system services (`systemctl` with the narrowly scoped Polkit rule). Low-battery system-service restoration must continue to use the recorded active-service list rather than starting every listed service unconditionally.
- Keep sysfs paths and KDE interface names literal and easy to audit. These files are installed as system configuration, so changes to udev, tmpfiles, Polkit, or systemd units require corresponding installer updates and careful privilege review.

## Documentation source of truth

`README.md` documents prerequisites, PowerDevil configuration, supported platforms, manual profile testing, and verification commands. Keep it consistent with runtime behavior, especially profile values, required KDE utilities, and installed system paths.

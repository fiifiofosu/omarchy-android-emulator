# Android Emulator (Omarchy widget)

Android Virtual Devices in the Omarchy bar, in the same shape as
[omarchy-dbforge](https://github.com/fiifiofosu/omarchy-dbforge): a small CLI
does the real work, a QML bar widget polls it and renders a panel.

There's no daemon here, on purpose. Unlike DBForge's database containers, an
AVD is already a long-running process (the emulator) with its own discovery
protocol (`adb`), so `emuctl` just shells out to Google's
[`android` CLI](https://developer.android.com/tools/agents/android-cli) and
`adb`, and reshapes their output into JSON.

## What it does

- Click the bar icon to see your AVDs and whether each is running.
- Toggle a switch to start or stop one.
- "New virtual device" expands a list of device profiles (phone/tablet/
  desktop sizes); picking one creates an AVD, downloading whatever system
  image it needs.
- The header's two buttons open a terminal running `emuctl doctor` (checks
  the `android` CLI, `adb`, and `/dev/kvm`) and `emuctl images` (lists
  installed/available system-image packages) — these are read/diagnostic
  surfaces large enough that they belong in a terminal, not the bar panel.

## Requirements

- [Android CLI](https://developer.android.com/tools/agents/android-cli/download)
  installed (the `android` binary). Install it with:
  ```sh
  curl -fsSL https://dl.google.com/android/cli/latest/linux_x86_64/install.sh | bash
  ```
- `/dev/kvm` for hardware-accelerated emulation (`emuctl doctor` checks this).
- Omarchy 4.0+.

## Install

```sh
./install.sh --enable
```

This installs `emuctl` to `~/.local/bin` and copies the widget into
`~/.config/omarchy/plugins/io.github.fiifiofosu.android-emulator/`. Re-run it
after pulling updates — Omarchy plugin folders can't contain symlinks, so the
installer copies files in rather than linking the repo.

Without `--enable`, the widget is installed but not placed on the bar; turn
it on later with:

```sh
omarchy plugin enable io.github.fiifiofosu.android-emulator
omarchy bar move io.github.fiifiofosu.android-emulator
```

## emuctl

The widget's backend is a standalone script, usable on its own:

```
emuctl doctor                Check that android CLI / adb / KVM are reachable
emuctl list [--json]         List AVDs and whether each is running
emuctl profiles              List device profiles usable with `create`
emuctl start <avd> [--cold] [--headless]
emuctl stop [<avd>]          Stop a running AVD (omit name if only one is running)
emuctl create <profile>      Create an AVD from a device profile (downloads as needed)
emuctl remove <avd> [--force]
emuctl images [--json]       List system-image packages (installed + available)
emuctl install <package>     android sdk install <package>
```

## Uninstall

```sh
./uninstall.sh
```

Removes the widget and `emuctl`. Your AVDs, the Android SDK, and the
`android` CLI itself are left alone.

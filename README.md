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
- "New virtual device" expands into a row of cards — **Pixel / Tablet /
  Legacy** — with avdmanager installed (see below); pick a card, then pick a
  device from the list under it (Pixel 6, Pixel 7 Pro, Nexus 5, ...) to create
  an AVD, downloading whatever system image it needs (a few hundred MB to a
  few GB the first time for a given API level — the panel shows live progress
  and an elapsed-time counter while that happens, not just a static "Creating…").
  Once it's created, the widget automatically starts it. There's no Samsung/
  OEM/iPhone card: Google's SDK only ships its own reference hardware (current
  Pixels + a few old Nexus phones), so "Legacy" is that leftover bucket, not a
  brand. Without avdmanager, this falls back to a flat list of the `android`
  CLI's own generic sizes (`small_phone`, `medium_phone`, ...).
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
- Optional: real Pixel device profiles (instead of generic sizes) need
  `avdmanager`, which isn't part of the `android` CLI itself. Install it with:
  ```sh
  emuctl enable-devices
  ```
  (this is `android sdk install cmdline-tools/latest` under the hood — a
  one-time, ~50MB download.)

## Install

```sh
./install.sh --enable
```

This installs `emuctl` to `~/.local/bin` and copies the widget into
`~/.config/omarchy/plugins/io.github.fiifiofosu.android-emulator/`. Re-run it
after pulling updates — Omarchy plugin folders can't contain symlinks, so the
installer copies files in rather than linking the repo. It also restarts the
Omarchy shell (`omarchy restart shell`) so an already-running bar actually
picks up the new code: copying files alone updates what's on disk, but a
widget that was already loaded keeps running its old QML until something
forces it to reload, which otherwise looks like the update silently didn't
take.

Without `--enable`, the widget is installed but not placed on the bar; turn
it on later with:

```sh
omarchy plugin enable io.github.fiifiofosu.android-emulator
omarchy bar move io.github.fiifiofosu.android-emulator
```

## emuctl

The widget's backend is a standalone script, usable on its own:

```
emuctl doctor                 Check that android CLI / adb / avdmanager / KVM are reachable
emuctl enable-devices         Install cmdline-tools for real device ids (pixel_6, ...)
emuctl list [--json]          List AVDs and whether each is running
emuctl profiles               List device ids/profiles usable with `create`
emuctl start <avd> [--cold] [--headless]
emuctl stop [<avd>]           Stop a running AVD (omit name if only one is running)
emuctl create <device-id-or-profile> [api-level]
                               Create an AVD (downloads its system image as needed;
                               api-level defaults to 34, only used with avdmanager)
emuctl remove <avd> [--force]
emuctl images [--json]        List system-image packages (installed + available)
emuctl install <package>      android sdk install <package>
```

## Uninstall

```sh
./uninstall.sh
```

Removes the widget and `emuctl`. Your AVDs, the Android SDK, and the
`android` CLI itself are left alone.

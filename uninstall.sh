#!/usr/bin/env bash
# Removes the Android Emulator widget from the Omarchy shell.
#
# This touches the widget and emuctl only. Your AVDs, the Android SDK, and
# the `android` CLI itself are left exactly as they were.
set -euo pipefail

PLUGIN_ID="io.github.fiifiofosu.android-emulator"
DEST="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/$PLUGIN_ID"
BIN="$HOME/.local/bin/emuctl"

say()  { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin remove "$PLUGIN_ID" --yes >/dev/null 2>&1 ||
    warn "omarchy could not remove the plugin; removing the folder directly"
fi

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  say "Removed $DEST"
else
  say "Nothing to remove at $DEST"
fi

if [ -f "$BIN" ]; then
  rm -f "$BIN"
  say "Removed $BIN"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
say "Done."

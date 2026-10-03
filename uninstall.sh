#!/usr/bin/env bash
# Removes the Android Emulator widget from the Omarchy shell.
#
# This touches the widget and emuctl only. Your AVDs, the Android SDK, and
# the `android` CLI itself are left exactly as they were.
set -euo pipefail

PLUGIN_ID="io.github.fiifiofosu.android-emulator"
DEST="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/$PLUGIN_ID"
BIN="$HOME/.local/bin/emuctl"
HYPR_FILE="$HOME/.config/hypr/hyprland.lua"
HYPR_RULE_BEGIN='-- >>> omarchy-android-emulator: float the emulator window >>>'
HYPR_RULE_END='-- <<< omarchy-android-emulator: float the emulator window <<<'

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

# Only strips the block install.sh's own marker comments bound -- a rule
# added by hand (without the markers) is left alone, same as how install.sh
# would have treated it as "already present" rather than its own to manage.
if [ -f "$HYPR_FILE" ] && grep -qF "$HYPR_RULE_BEGIN" "$HYPR_FILE"; then
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Remove the Hyprland float rule this plugin added to hyprland.lua? [y/N] '
    read -r reply
  else
    reply=n
  fi
  case "$reply" in
    [Yy]*)
      cp "$HYPR_FILE" "$HYPR_FILE.bak.$(date +%s)"
      sed -i "/^$(printf '%s' "$HYPR_RULE_BEGIN" | sed 's/[.[\*^$/]/\\&/g')\$/,/^$(printf '%s' "$HYPR_RULE_END" | sed 's/[.[\*^$/]/\\&/g')\$/d" "$HYPR_FILE"
      say "Removed the Hyprland float rule from hyprland.lua"
      command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
      ;;
    *) say "Left the Hyprland float rule in hyprland.lua" ;;
  esac
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
say "Done."

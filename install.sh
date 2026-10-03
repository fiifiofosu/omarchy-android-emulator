#!/usr/bin/env bash
# Installs emuctl and the Android Emulator widget into the Omarchy shell.
#
# Omarchy loads plugins from ~/.config/omarchy/plugins/<id>/ and the plugin
# guide forbids symlinks inside a plugin folder, so this copies the files in
# rather than linking the repo. That means it has to be re-run after a pull.
set -euo pipefail

PLUGIN_ID="io.github.fiifiofosu.android-emulator"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/$PLUGIN_ID"
BIN_DEST="${HOME}/.local/bin"
HYPR_FILE="$HOME/.config/hypr/hyprland.lua"
HYPR_RULE_SENTINEL='o.window({ class = "^Emulator$" }, { float = true })'
HYPR_RULE_BEGIN='-- >>> omarchy-android-emulator: float the emulator window >>>'
HYPR_RULE_END='-- <<< omarchy-android-emulator: float the emulator window <<<'

# Enabling edits ~/.config/omarchy/shell.json and puts the widget on the bar;
# the Hyprland rule edits hyprland.lua so the emulator floats instead of
# tiling full-screen. Both are the user's configuration, not ours, so both
# are asked about rather than applied silently -- --enable/--no-enable and
# --hypr-rule/--no-hypr-rule answer ahead of time, for scripts and for a
# non-interactive shell, where the default for both is "don't touch it".
ENABLE=""
HYPR_RULE=""
for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE=yes ;;
    --no-enable) ENABLE=no ;;
    --hypr-rule) HYPR_RULE=yes ;;
    --no-hypr-rule) HYPR_RULE=no ;;
    -h|--help)
      echo "Usage: install.sh [--enable | --no-enable] [--hypr-rule | --no-hypr-rule]"
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Without this, Hyprland tiles the emulator like any other window -- as the
# sole/largest tile it fills most of the screen, phone content letterboxed in
# black. Idempotent via a sentinel grep (matches whether the line got there
# through this function or was added by hand before this existed), backs up
# hyprland.lua before writing, and checks `hyprctl configerrors` after
# reloading so a malformed edit doesn't silently leave Hyprland broken.
add_hypr_rule() {
  if [ ! -f "$HYPR_FILE" ]; then
    warn "$HYPR_FILE not found; skipping the Hyprland float rule"
    return 0
  fi
  if grep -qF "$HYPR_RULE_SENTINEL" "$HYPR_FILE"; then
    say "Hyprland float rule already present in hyprland.lua"
    return 0
  fi

  local backup="$HYPR_FILE.bak.$(date +%s)"
  cp "$HYPR_FILE" "$backup"

  {
    echo ""
    echo "$HYPR_RULE_BEGIN"
    echo '-- Android Emulator: float it with a phone-shaped size instead of tiling.'
    echo '-- Floating is matched on class alone (not the full title) because the'
    echo '-- window is created titled just "Emulator" and only renames itself to'
    echo '-- "Android Emulator - <avd>:<port>" after the guest boots -- a'
    echo '-- title-only match would race that rename and intermittently miss the'
    echo '-- window.'
    echo "$HYPR_RULE_SENTINEL"
    echo 'o.window({ class = "^Emulator$", title = "^Android Emulator - .*$" }, {'
    echo '  center = true,'
    echo '  size = { 420, 900 },'
    echo '})'
    echo "$HYPR_RULE_END"
  } >> "$HYPR_FILE"
  say "Added the Hyprland float rule to hyprland.lua (backup: $(basename "$backup"))"

  if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
    local errs
    errs="$(hyprctl configerrors 2>/dev/null || true)"
    if [ -n "$errs" ]; then
      warn "hyprctl reported config errors after adding the rule -- restoring the backup:"
      warn "$errs"
      cp "$backup" "$HYPR_FILE"
      hyprctl reload >/dev/null 2>&1 || true
    else
      say "Reloaded Hyprland"
    fi
  fi
}

command -v omarchy >/dev/null 2>&1 ||
  die "omarchy is not on PATH; this widget needs Omarchy 4.0 or newer"

command -v android >/dev/null 2>&1 || [ -x "$HOME/.local/bin/android" ] ||
  warn "the 'android' CLI is not installed yet -- see https://developer.android.com/tools/agents/android-cli/download"

mkdir -p "$BIN_DEST"
install -m 0755 "$HERE/emuctl" "$BIN_DEST/emuctl"
say "Installed emuctl to $BIN_DEST/emuctl"
case ":$PATH:" in
  *":$BIN_DEST:"*) ;;
  *) warn "$BIN_DEST is not on PATH in this shell; the widget finds emuctl there regardless" ;;
esac

# Validate before touching the user's config, so a broken manifest never
# becomes an installed plugin the shell has to cope with.
omarchy plugin validate "$HERE" || die "plugin validation failed"
say "Validated $PLUGIN_ID"

mkdir -p "$DEST"
for f in manifest.json Panel.qml Service.qml AndroidIcon.qml Model.js README.md LICENSE; do
  install -m 0644 "$HERE/$f" "$DEST/$f"
done
say "Installed to $DEST"

# rescanPlugins discovers a *new* plugin fine, but on an update it does not
# make an already-loaded widget re-read its QML from disk -- a bar that was
# already running the old Panel.qml keeps running it until something forces
# a reload. Installed-file diffs alone can't tell "first install" from
# "update to a plugin already enabled", so this always restarts the shell
# rather than risk silently serving stale QML after every `git pull`.
if command -v omarchy >/dev/null 2>&1 && pgrep -x quickshell >/dev/null 2>&1; then
  omarchy restart shell >/dev/null 2>&1
  say "Restarted the Omarchy shell to pick up the latest widget code"
else
  warn "omarchy-shell is not running; the widget appears on next login"
fi

if [ -z "$HYPR_RULE" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Add the recommended Hyprland rule so the emulator floats instead of tiling full-screen? [Y/n] '
    read -r reply
    case "$reply" in [Nn]*) HYPR_RULE=no ;; *) HYPR_RULE=yes ;; esac
  else
    HYPR_RULE=no
  fi
fi

if [ "$HYPR_RULE" = yes ]; then
  add_hypr_rule
else
  say "Skipped the Hyprland float rule. Add it later -- see the README's"
  say "'Hyprland: float the emulator window' section, or re-run with --hypr-rule."
fi

if [ -z "$ENABLE" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Put the Android Emulator widget on your bar now? [y/N] '
    read -r reply
    case "$reply" in [Yy]*) ENABLE=yes ;; *) ENABLE=no ;; esac
  else
    ENABLE=no
  fi
fi

if [ "$ENABLE" != yes ]; then
  say "Installed but not enabled. Turn it on with:"
  say "  omarchy plugin enable $PLUGIN_ID"
  exit 0
fi

# Discovery is asynchronous, so a rescan that has returned is not a rescan
# that has finished. Retry briefly rather than racing it.
enabled=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1; then
    enabled=true
    break
  fi
  sleep 0.5
done

if $enabled; then
  say "Enabled $PLUGIN_ID"
else
  warn "could not enable automatically; run: omarchy plugin enable $PLUGIN_ID"
fi

say "Done. Place it with: omarchy bar move $PLUGIN_ID"

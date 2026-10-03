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

# Enabling edits ~/.config/omarchy/shell.json and puts the widget on the bar,
# which is the user's configuration, not ours. Copying the plugin in is not
# the same decision as turning it on, so the two are asked separately.
# --enable/--no-enable answer ahead of time, for scripts and for a
# non-interactive shell, where the default is to install without enabling.
ENABLE=""
for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE=yes ;;
    --no-enable) ENABLE=no ;;
    -h|--help)
      echo "Usage: install.sh [--enable | --no-enable]"
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

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

# A running shell has already scanned its plugin directory, and it cannot
# enable a plugin it has not discovered yet. So rescan first, then enable.
if omarchy-shell shell rescanPlugins >/dev/null 2>&1; then
  say "Rescanned plugins"
else
  warn "omarchy-shell is not running; the widget appears on next login"
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

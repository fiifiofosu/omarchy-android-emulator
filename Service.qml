import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to the Android SDK through emuctl, the small CLI shipped alongside
// this widget. emuctl itself is a thin wrapper over Google's `android` CLI
// and `adb` -- going straight to those from QML would mean re-deriving SDK
// paths and running-device detection inside the shell process for no gain.
Item {
  id: root

  property var settings: ({})

  property var avds: []
  property var summary: Model.summarize([])
  // { grouped: false, flat: [...] } or { grouped: true, categories: [...], byCategory: {...} }
  property var profiles: ({ grouped: false, flat: [] })
  property string selectedCategory: ""
  property bool missingBinary: false
  property bool refreshing: false
  property string lastError: ""
  property string actionStatus: ""
  property bool profilesOpen: false

  // The flat list the panel actually renders under the cards: the selected
  // category's devices when grouped, or everything when there's nothing to
  // group.
  readonly property var visibleProfiles: {
    if (!profiles.grouped) return profiles.flat || []
    return profiles.byCategory[selectedCategory] || []
  }

  readonly property string emuctlPath: _emuctl
  readonly property bool ready: _emuctl !== ""
  readonly property bool busy: actionProcess.running
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 8, 2, 3600)

  property string _emuctl: ""
  property bool _resolved: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // A user-manager shell's PATH has no ~/.local/bin, so emuctl is looked up
  // the same places the installer puts it before falling back to PATH.
  function resolveBinary() {
    if (resolveProcess.running) return
    resolveProcess.command = [
      "sh", "-c",
      'hint="$1"\n' +
      'if [ -n "$hint" ] && [ -x "$hint" ]; then printf "%s\\n" "$hint"; exit 0; fi\n' +
      'for p in "$HOME/.local/bin/emuctl" "/usr/local/bin/emuctl" "/usr/bin/emuctl"; do\n' +
      '  if [ -x "$p" ]; then printf "%s\\n" "$p"; exit 0; fi\n' +
      'done\n' +
      'command -v emuctl 2>/dev/null || true\n',
      "sh",
      String(setting("emuctlPath", ""))
    ]
    resolveProcess.running = true
  }

  function refresh() {
    if (!_resolved) { resolveBinary(); return }
    if (_emuctl === "") { missingBinary = true; return }
    if (listProcess.running) return
    refreshing = true
    listProcess.command = [_emuctl, "list", "--json"]
    listProcess.running = true
  }

  function applyList(raw) {
    var parsed = Model.parseList(raw)
    if (!parsed.ok) {
      lastError = parsed.error
      return
    }
    avds = parsed.avds
    summary = Model.summarize(parsed.avds)
    missingBinary = false
    lastError = ""
  }

  function start(id) { runAction([_emuctl, "start", id], "Starting " + id + "…") }
  function stop(id) { runAction([_emuctl, "stop", id], "Stopping " + id + "…") }

  function toggleAvd(avd) {
    if (!avd || busy) return
    if (Model.isRunning(avd)) stop(avd.id)
    else start(avd.id)
  }

  function createFromProfile(profile) {
    profilesOpen = false
    runAction([_emuctl, "create", profile], "Creating " + profile + "… (this can download several hundred MB)")
  }

  function runAction(command, message) {
    if (!ready || actionProcess.running) return
    actionStatus = message
    lastError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function loadProfiles() {
    if (!ready || profilesProcess.running) return
    profilesProcess.command = [_emuctl, "profiles"]
    profilesProcess.running = true
  }

  function selectCategory(cat) { selectedCategory = cat }

  readonly property bool profilesLoaded: profiles.grouped ? profiles.categories.length > 0 : profiles.flat.length > 0

  function toggleProfiles() {
    profilesOpen = !profilesOpen
    if (profilesOpen && !profilesLoaded) loadProfiles()
  }

  // Doctor output and the full SDK package list are read-only and can be
  // long, so they are opened in a terminal rather than crammed into the
  // panel.
  function openInTerminal(args) {
    Quickshell.execDetached([
      "sh", "-c",
      'cmd="$1"; shift\n' +
      'if command -v omarchy-launch-tui >/dev/null 2>&1; then exec omarchy-launch-tui "$cmd" "$@"; fi\n' +
      'exec uwsm-app -- xdg-terminal-exec -e "$cmd" "$@"\n',
      "sh", _emuctl
    ].concat(args))
  }

  function openDoctor() { openInTerminal(["doctor"]) }
  function openSdkManager() { openInTerminal(["images"]) }

  Component.onCompleted: resolveBinary()

  onSettingsChanged: {
    _resolved = false
    resolveBinary()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root._resolved
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Starting/creating an AVD takes a while, so poll a handful of times after
  // an action instead of leaving the row stale until the next periodic
  // refresh.
  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 2000
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 10) { ticks = 0; running = false; root.actionStatus = "" }
    }
  }

  Process {
    id: resolveProcess
    running: false
    command: []
    stdout: StdioCollector { id: resolveOut; waitForEnd: true }
    onExited: function(exitCode) {
      root._emuctl = String(resolveOut.text || "").trim()
      root._resolved = true
      root.missingBinary = root._emuctl === ""
      if (root._emuctl !== "") root.refresh()
    }
  }

  Process {
    id: listProcess
    running: false
    command: []
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) {
        root.applyList(String(listOut.text || ""))
        return
      }
      root.avds = []
      root.summary = Model.summarize([])
      root.lastError = Model.elide(String(listErr.text || "") || "emuctl list failed")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = Model.elide(String(actionErr.text || actionOut.text || "") || "Command failed")
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: profilesProcess
    running: false
    command: []
    stdout: StdioCollector { id: profilesOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var parsed = Model.parseProfiles(String(profilesOut.text || ""))
      root.profiles = parsed
      if (parsed.grouped && (root.selectedCategory === "" || parsed.categories.indexOf(root.selectedCategory) === -1)) {
        root.selectedCategory = parsed.categories[0] || ""
      }
    }
  }
}

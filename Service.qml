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
  readonly property bool busy: actionProcess.running || createProcess.running
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 8, 2, 3600)

  property bool creating: false
  property int creatingElapsedSec: 0
  property string _createLastLine: ""

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

  // Deleting a running AVD out from under the emulator process is asking for
  // trouble, so it's stopped first and removed once that settles rather than
  // racing the two.
  function removeAvd(avd) {
    if (!avd || busy) return
    if (Model.isRunning(avd)) {
      runAction([_emuctl, "stop", avd.id], "Stopping " + avd.id + " before delete…")
      _pendingRemoval = avd.id
      return
    }
    runAction([_emuctl, "remove", avd.id, "--force"], "Deleting " + avd.id + "…")
  }

  property string _pendingRemoval: ""

  // Creating an AVD can mean downloading a multi-hundred-MB system image, so
  // unlike start/stop this doesn't go through the quick runAction() path: it
  // gets its own long-lived process whose stdout is streamed live into
  // actionStatus (see createProcess below) instead of being collected only
  // at exit, plus an elapsed-time counter, so the panel always shows that
  // something is actually happening rather than going quiet for minutes.
  function createFromProfile(profile) {
    if (!ready || createProcess.running) return
    profilesOpen = false
    creating = true
    creatingElapsedSec = 0
    _createLastLine = ""
    actionStatus = "Creating " + profile + "…"
    lastError = ""
    createProcess.command = [_emuctl, "create", profile]
    createProcess.running = true
    createElapsedTimer.restart()
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
  // panel. `-e` terminals close the instant the command exits, and
  // `emuctl doctor`/`images` typically finish in a few seconds -- without a
  // pause the window opens and closes too fast to read anything, success or
  // failure alike. So the actual `-e` target is a small wrapper that runs
  // emuctl and then waits for a keypress before letting the terminal close.
  function openInTerminal(args) {
    Quickshell.execDetached([
      "sh", "-c",
      'emuctl="$1"; shift\n' +
      // No leading "exec": that would replace this process with emuctl's, so
      // the pause after it would never run -- it has to be a plain call.
      'inner=\'"$0" "$@" 2>&1; echo; printf "(press Enter to close)"; read -r _\'\n' +
      'if command -v omarchy-launch-tui >/dev/null 2>&1; then exec omarchy-launch-tui sh -c "$inner" "$emuctl" "$@"; fi\n' +
      'exec uwsm-app -- xdg-terminal-exec -e sh -c "$inner" "$emuctl" "$@"\n',
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
      // 60s: a cold emulator boot (common right after `create`) can take well
      // past DBForge's container-sized settle window.
      if (ticks >= 30) { ticks = 0; running = false; root.actionStatus = "" }
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
        root._pendingRemoval = ""
      } else if (root._pendingRemoval !== "") {
        var id = root._pendingRemoval
        root._pendingRemoval = ""
        root.actionStatus = "Deleting " + id + "…"
        actionProcess.command = [root._emuctl, "remove", id, "--force"]
        actionProcess.running = true
        return
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }

  Timer {
    id: createElapsedTimer
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      root.creatingElapsedSec += 1
      if (root._createLastLine !== "") {
        root.actionStatus = root._createLastLine + " (" + root.creatingElapsedSec + "s)"
      }
    }
  }

  Process {
    id: createProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var t = String(line || "").trim()
        if (t !== "") root._createLastLine = t
      }
    }
    stderr: StdioCollector { id: createErr; waitForEnd: true }
    onExited: function(exitCode) {
      createElapsedTimer.stop()
      root.creating = false
      if (exitCode === 0) {
        // cmd_create's contract is to print the actual AVD name as its last
        // line, which can differ from the device id it was asked for (ids
        // with spaces, like "Nexus 7 2013", get sanitized into the name) --
        // so this is what's actually passed to `start`, not the id the
        // panel originally clicked.
        var createdName = root._createLastLine
        root.actionStatus = createdName !== "" ? "Created " + createdName + ", starting…" : "Created, starting…"
        if (createdName !== "") root.start(createdName)
      } else {
        root.lastError = Model.elide(String(createErr.text || "") || root._createLastLine || "emuctl create failed")
        root.actionStatus = ""
      }
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

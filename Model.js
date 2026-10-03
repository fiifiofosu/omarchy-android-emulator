// Pure data helpers for the Android Emulator bar widget.
//
// Everything that turns `emuctl list --json` into something the panel can
// render lives here, so the shaping rules stay in one readable place and the
// QML is left to do layout.

.pragma library

// parseList turns raw stdout into a sorted AVD array.
//
// `emuctl list --json` prints `[]` for an empty list (never bare `null`,
// unlike dbctl), but the array check is kept anyway since a future emuctl
// build is not a contract this file should assume about.
function parseList(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, avds: [] }
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { ok: false, avds: [], error: "Could not read emuctl output" }
  }
  if (!parsed) return { ok: true, avds: [] }
  if (!Array.isArray(parsed)) return { ok: false, avds: [], error: "Unexpected emuctl output" }

  var out = []
  for (var i = 0; i < parsed.length; i++) {
    var it = parsed[i]
    if (!it || !it.id) continue
    out.push({
      id: String(it.id),
      detail: String(it.detail || ""),
      status: String(it.status || "stopped"),
      port: Number(it.port || 0)
    })
  }
  return { ok: true, avds: sortForDisplay(out) }
}

// sortForDisplay puts running AVDs first, then alphabetically, so the list
// does not reshuffle between refreshes.
function sortForDisplay(avds) {
  var copy = (avds || []).slice()
  copy.sort(function(a, b) {
    var r = (b.status === "running" ? 1 : 0) - (a.status === "running" ? 1 : 0)
    if (r !== 0) return r
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
  })
  return copy
}

function isRunning(avd) {
  return !!avd && avd.status === "running"
}

function summarize(avds) {
  var running = 0, stopped = 0
  for (var i = 0; i < (avds || []).length; i++) {
    if (isRunning(avds[i])) running += 1
    else stopped += 1
  }
  return { running: running, stopped: stopped, total: (avds || []).length }
}

function summaryText(summary, offline) {
  if (offline) return "android CLI not found"
  if (!summary || summary.total === 0) return "No AVDs yet"
  var parts = [summary.running + " running"]
  if (summary.stopped > 0) parts.push(summary.stopped + " stopped")
  return parts.join(" · ")
}

// barLabel is the text beside the bar icon: a single number, or nothing when
// there is nothing worth a click.
function barLabel(summary, offline) {
  if (offline) return ""
  if (!summary || summary.running === 0) return ""
  return String(summary.running)
}

// rowMeta is the dim second line of an AVD row.
function rowMeta(avd) {
  if (!avd) return ""
  if (avd.status === "running" && avd.port > 0) return "running · emulator-" + avd.port
  return avd.status
}

// elide keeps a command's error output to something a panel can show.
function elide(text, limit) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var cap = limit || 140
  return value.length > cap ? value.substring(0, cap - 1) + "…" : value
}

// parseProfiles turns `emuctl profiles` into an array of {id, label}.
//
// Without avdmanager each line is a bare generic size ("medium_phone"), so id
// and label are the same string. With avdmanager each line is
// "id<TAB>Display Name" (e.g. "pixel_6\tPixel 6"), so the panel can show the
// friendly name while `create` still gets the id.
function parseProfiles(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var t = lines[i].trim()
    if (t === "") continue
    var tab = t.indexOf("\t")
    if (tab === -1) out.push({ id: t, label: t })
    else out.push({ id: t.substring(0, tab).trim(), label: t.substring(tab + 1).trim() })
  }
  return out
}

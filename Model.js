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
      port: Number(it.port || 0),
      serial: String(it.serial || ""),
      error: String(it.error || "")
    })
  }
  return { ok: true, avds: sortForDisplay(out) }
}

// sortForDisplay puts live AVDs (starting, booting or running) first, then
// alphabetically, so the list does not reshuffle between refreshes.
function sortForDisplay(avds) {
  var copy = (avds || []).slice()
  copy.sort(function(a, b) {
    var r = (isActive(b) ? 1 : 0) - (isActive(a) ? 1 : 0)
    if (r !== 0) return r
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)
  })
  return copy
}

// emuctl reports one of: stopped, starting (qemu is up, adb can't see it
// yet), booting (on adb, Android not done booting), running (booted and
// usable), failed (a start died before reaching running).
//
// isActive is "there's an emulator process for this AVD" -- what the toggle
// shows as on, and what a click stops. isReady is the narrower "booted", the
// only state where adb-driven actions (screenshot, APK install, ...) work.
function isActive(avd) {
  return !!avd && (avd.status === "running" || avd.status === "booting" || avd.status === "starting")
}

function isReady(avd) {
  return !!avd && avd.status === "running"
}

function isTransitional(avd) {
  return !!avd && (avd.status === "booting" || avd.status === "starting")
}

function summarize(avds) {
  var running = 0, booting = 0, failed = 0, stopped = 0
  for (var i = 0; i < (avds || []).length; i++) {
    var s = avds[i].status
    if (s === "running") running += 1
    else if (isTransitional(avds[i])) booting += 1
    else if (s === "failed") failed += 1
    else stopped += 1
  }
  return {
    running: running,
    booting: booting,
    failed: failed,
    stopped: stopped,
    active: running + booting,
    total: (avds || []).length
  }
}

function summaryText(summary, offline) {
  if (offline) return "android CLI not found"
  if (!summary || summary.total === 0) return "No AVDs yet"
  var parts = [summary.running + " running"]
  if (summary.booting > 0) parts.push(summary.booting + " booting")
  if (summary.failed > 0) parts.push(summary.failed + " failed")
  if (summary.stopped > 0) parts.push(summary.stopped + " stopped")
  return parts.join(" · ")
}

// barLabel is the text beside the bar icon: a single number, or nothing when
// there is nothing worth a click.
function barLabel(summary, offline) {
  if (offline) return ""
  if (!summary || summary.active === 0) return ""
  return String(summary.active)
}

// rowMeta is the dim second line of an AVD row.
function rowMeta(avd) {
  if (!avd) return ""
  if (avd.status === "running" && avd.port > 0) return "running · emulator-" + avd.port
  if (avd.status === "booting" && avd.port > 0) return "booting… · emulator-" + avd.port
  if (avd.status === "starting") return "starting…"
  if (avd.status === "failed") return "failed: " + (avd.error || "emulator exited")
  return avd.status
}

// parsePorts turns the "reversePorts" setting ("8081, 19000") into a list of
// valid TCP port strings, dropping anything that isn't one.
function parsePorts(value) {
  var out = []
  var parts = String(value || "").split(/[\s,]+/)
  for (var i = 0; i < parts.length; i++) {
    var n = parseInt(parts[i], 10)
    if (isFinite(n) && n > 0 && n < 65536 && String(n) === parts[i]) out.push(String(n))
  }
  return out
}

// elide keeps a command's error output to something a panel can show.
function elide(text, limit) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var cap = limit || 140
  return value.length > cap ? value.substring(0, cap - 1) + "…" : value
}

// The fixed left-to-right order for the brand cards. Categories not present
// in a given `emuctl profiles` run (e.g. an older emuctl before this existed)
// just don't get a card.
var CATEGORY_ORDER = ["pixel", "tablet", "legacy"]
var CATEGORY_LABEL = { pixel: "Pixel", tablet: "Tablet", legacy: "Legacy" }

// parseProfiles turns `emuctl profiles` into either a grouped or a flat
// result, depending on what emuctl could offer:
//
// Without avdmanager, each line is a bare generic size ("medium_phone") with
// no category -- there's nothing to split into cards, so this returns
// { grouped: false, flat: [{id, label}] }.
//
// With avdmanager, each line is "category<TAB>id<TAB>Display Name" (e.g.
// "pixel\tpixel_6\tPixel 6"). This returns
// { grouped: true, categories: [...], byCategory: { pixel: [...], ... } },
// with categories in CATEGORY_ORDER and only the ones actually present.
function parseProfiles(raw) {
  var lines = String(raw || "").split("\n")
  var flat = []
  var byCategory = {}
  var grouped = false

  for (var i = 0; i < lines.length; i++) {
    var t = lines[i].trim()
    if (t === "") continue
    var first = t.indexOf("\t")
    if (first === -1) { flat.push({ id: t, label: t }); continue }
    var second = t.indexOf("\t", first + 1)
    if (second === -1) {
      flat.push({ id: t.substring(0, first).trim(), label: t.substring(first + 1).trim() })
      continue
    }
    grouped = true
    var cat = t.substring(0, first).trim()
    var id = t.substring(first + 1, second).trim()
    var label = t.substring(second + 1).trim()
    if (!byCategory[cat]) byCategory[cat] = []
    byCategory[cat].push({ id: id, label: label })
  }

  if (!grouped) return { grouped: false, flat: flat }

  var categories = []
  for (var c = 0; c < CATEGORY_ORDER.length; c++) {
    if (byCategory[CATEGORY_ORDER[c]]) categories.push(CATEGORY_ORDER[c])
  }
  for (var k in byCategory) {
    if (categories.indexOf(k) === -1) categories.push(k)
  }
  return { grouped: true, categories: categories, byCategory: byCategory }
}

function categoryLabel(cat) {
  return CATEGORY_LABEL[cat] || cat
}

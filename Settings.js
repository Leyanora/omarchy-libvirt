// Reading and writing the widget's shell.json entry. Pure: no QML, no state.

// The three colour fields, in the order the settings view lists them.
var COLOR_SETTINGS = [
  { name: "colorRunning", label: "Running" },
  { name: "colorPaused", label: "Paused" },
  { name: "colorStopped", label: "Shut off" }
]

// The connection picker is an allowlist: a URI reaches virsh only by being one
// of these, or by already being the hand-edited value in the entry.
var CONNECTION_OPTIONS = [
  { value: "qemu:///session", label: "Session — this user" },
  { value: "qemu:///system", label: "System — host-wide" }
]

// The booleans the settings view offers, in the order it lists them.
var BEHAVIOUR_SETTINGS = [
  { name: "showCount", label: "Show the running count",
    description: "Puts the number of running domains next to the bar glyph." },
  { name: "showSnapshots", label: "Snapshot button in the expanded row",
    description: "" },
  { name: "confirmForceOff", label: "Confirm force off",
    description: "Force off discards unwritten guest state." },
  { name: "confirmDiscardSaved", label: "Confirm discarding saved state",
    description: "" },
  { name: "confirmSnapshotRevert", label: "Confirm snapshot revert and delete",
    description: "" }
]

// Options plus the current value, so a hand-edited URI stays selectable.
function connectionOptions(current) {
  var out = CONNECTION_OPTIONS.slice()
  for (var i = 0; i < out.length; i++)
    if (out[i].value === current) return out
  out.push({ value: current, label: current })
  return out
}

// Checked before persisting: nothing but a listed URI may reach a virsh call.
function isKnownUri(options, value) {
  for (var i = 0; i < options.length; i++)
    if (options[i].value === value) return true
  return false
}

function read(entry, name, fallback) {
  var value = entry ? entry[name] : undefined
  return value === undefined || value === null ? fallback : value
}

// updateEntryInline replaces the entry wholesale, so every other key is copied over.
function mergeEntry(entry, moduleName, name, value) {
  var next = { id: moduleName }
  for (var existing in entry) if (existing !== "id") next[existing] = entry[existing]
  next[name] = value
  return next
}

// Rejected rather than handed to a color property, which reads a bad string as black.
function isColorHex(value) {
  return /^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(String(value).trim())
}

// Preset swatches for the colour picker. The three plugin defaults are in here
// deliberately, so the reset value is also reachable by one click.
var PRESETS = [
  "#f85149", "#fb8500", "#d29922", "#e3b341",
  "#3fb950", "#2dd4bf", "#39c5cf", "#58a6ff",
  "#6e7bf2", "#bc8cff", "#f778ba", "#8b949e"
]

function clamp01(value) {
  return Math.max(0, Math.min(1, Number(value) || 0))
}

// 0..1 to a 0..255 channel, which is what the R/G/B fields read and write.
function channel(value) {
  return Math.round(clamp01(value) * 255)
}

// Built from three 0..1 floats rather than a QML color, to keep this file pure.
function hexOf(r, g, b) {
  var parts = [channel(r), channel(g), channel(b)]
  var out = "#"
  for (var i = 0; i < parts.length; i++)
    out += (parts[i] < 16 ? "0" : "") + parts[i].toString(16)
  return out
}

// Reading and writing the widget's shell.json entry. Pure: no QML, no state.

// The three colour fields, in the order the settings view lists them.
var COLOR_SETTINGS = [
  { name: "colorRunning", label: "Running" },
  { name: "colorPaused", label: "Paused" },
  { name: "colorStopped", label: "Shut off" }
]

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

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

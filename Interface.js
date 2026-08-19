// Strings and glyphs the popup renders. Pure: no QML, no state.

// Host tooltips are AutoText and out of reach: with no `<`, nothing parses as markup.
function plain(value) {
  return String(value).replace(/</g, "")
}

// Named once, so no call site has to carry a glyph literal no reader can identify.
var Glyph = {
  widget: "󰒋",
  back: "󰅁",
  settings: "󰒓",
  refresh: "󰑓",
  working: "󰇙",
  restore: "󰦛",
  start: "󰐊",
  shutdown: "󰓛",
  forceOff: "󱐋",
  collapse: "󰅃",
  expand: "󰅀",
  pause: "󰏤",
  reboot: "󰜉",
  save: "󰆓",
  discard: "󰆴",
  snapshots: "󰄄",
  revert: "󰑐",
  create: "󰐕",
  manager: "󰍹"
}

function connectionLabel(down) {
  return down ? "Disconnected" : "Connected"
}

// lastError wins: with the connection down the counts mean nothing.
function summaryText(lastError, total, running, uri) {
  if (lastError !== "") return lastError
  if (total === 0) return "No domains on " + uri
  return running + " of " + total + " running"
}

function barText(icon, count, showLabel) {
  return showLabel ? (icon + "  " + count) : icon
}

// settingsError first: the user just caused it, by hand.
function errorText(settingsError, lastError, actionError, crashError) {
  if (settingsError !== "") return settingsError
  if (lastError !== "") return lastError
  return actionError !== "" ? actionError : crashError
}

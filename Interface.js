// Strings and glyphs the popup renders. Pure: no QML, no state.

// Host tooltips are AutoText and out of reach: with no `<`, nothing parses as markup.
function plain(value) {
  return String(value).replace(/</g, "")
}

// The domain count a filter field starts earning its row.
var FILTER_MIN = 8

// Seconds a queued shutdown may go unanswered before the row says so.
var STALL_AFTER = 20

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
  manager: "󰍹",
  palette: "󰏘",
  search: "󰍉",
  current: "󰄬"
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

// The bar tooltip names what is up rather than counting it; the `<` guard is
// applied at the call site, which is where lastError needs it too.
function barTooltip(lastError, domains, running, uri) {
  var head = summaryText(lastError, domains.length, running, uri)
  if (lastError !== "" || running === 0) return head
  var lines = [head]
  var listed = 0
  for (var i = 0; i < domains.length && listed < 6; i++) {
    if (domains[i].domainState !== "running") continue
    lines.push("  " + domains[i].name)
    listed++
  }
  if (running > listed) lines.push("  and " + (running - listed) + " more")
  return lines.join("\n")
}

// The full name only earns the tooltip when the row had to cut it short, and it
// is stripped here: this one goes straight into a PanelToolTip, which is AutoText.
function nameTooltip(name, truncated, consoleReady) {
  var parts = []
  if (truncated) parts.push(plain(name))
  if (consoleReady) parts.push("Open console")
  return parts.join(" — ")
}

// vCPU/memory come from dominfo, the reason only from domstate, and either can be
// missing while the two probes are still in flight.
function detailLine(detail, reason) {
  var parts = []
  if (detail.cpus > 0) parts.push(detail.cpus + " vCPU")
  if (detail.memory !== "") parts.push(detail.memory)
  if (reason !== "") parts.push(reason)
  return parts.join("  ·  ")
}

// Named rather than counted: a queued shutdown looks identical to a dead button.
function stalledTooltip(seconds) {
  return "Still running " + seconds + "s after shut down — force off"
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

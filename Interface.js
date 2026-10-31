.import "Virsh.js" as Virsh

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
  current: "󰄬",
  cpu: "󰻠",
  memory: "󰍛"
}

// CPU at or past this reads urgent, in the row and nowhere else.
var CPU_HOT = 90

// The bar has room for this many domains, and for this much of each name.
var BAR_STATS_MAX = 3
var BAR_NAME_MAX = 12

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
function barTooltip(lastError, domains, running, uri, stats) {
  var head = summaryText(lastError, domains.length, running, uri)
  if (lastError !== "" || running === 0) return head
  var lines = [head]
  var listed = 0
  for (var i = 0; i < domains.length && listed < 6; i++) {
    if (domains[i].domainState !== "running") continue
    var usage = stats ? stats[Virsh.key(domains[i].name)] : undefined
    lines.push("  " + domains[i].name + (usage ? "  " + usageLine(usage) : ""))
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
// A running domain's sample replaces the static figures with what it is using of them.
function detailLine(detail, reason, usage) {
  var parts = []
  if (usage && usage.cpu >= 0) parts.push(usage.cpu + "% of " + usage.vcpus + " vCPU")
  else if (detail.cpus > 0) parts.push(detail.cpus + " vCPU")
  if (usage && usage.memTotal > 0) parts.push(memoryOf(usage.memUsed, usage.memTotal))
  else if (detail.memory !== "") parts.push(detail.memory)
  if (reason !== "") parts.push(reason)
  return parts.join("  ·  ")
}

// Named rather than counted: a queued shutdown looks identical to a dead button.
function stalledTooltip(seconds) {
  return "Still running " + seconds + "s after shut down — force off"
}

// `-1` is the first sample, which has nothing to take a difference from yet.
function cpuText(usage) {
  return usage && usage.cpu >= 0 ? usage.cpu + "%" : "–"
}

// One unit for both halves, the total's, so it never reads `512 MiB / 4 GiB`.
function memoryOf(usedKiB, totalKiB) {
  var gib = totalKiB >= 1024 * 1024
  var scale = gib ? 1024 * 1024 : 1024
  var used = Math.round(usedKiB / scale * 10) / 10
  var total = Math.round(totalKiB / scale * 10) / 10
  return used + " / " + total + (gib ? " GiB" : " MiB")
}

function usageLine(usage) {
  return "CPU " + cpuText(usage) + "  ·  RAM " + memoryOf(usage.memUsed, usage.memTotal)
}

// Running domains only, narrowed to `selected` unless it is empty.
function barStatsText(domains, stats, selected, showNames, nameLength, aliases, showMemory) {
  var limit = Math.max(1, Math.min(40, Math.round(Number(nameLength) || BAR_NAME_MAX)))
  var parts = []
  var more = 0
  for (var i = 0; i < domains.length; i++) {
    var name = domains[i].name
    if (domains[i].domainState !== "running") continue
    if (selected.length > 0 && selected.indexOf(name) < 0) continue
    var usage = stats[Virsh.key(name)]
    if (!usage) continue
    if (parts.length >= BAR_STATS_MAX) {
      more++
      continue
    }
    var alias = aliases && aliases[Virsh.key(name)]
    var label = typeof alias === "string" && alias.trim() !== "" ? alias.trim() : name
    // Count Unicode code points, so truncation never splits a surrogate pair.
    var chars = Array.from(label)
    var short = chars.length > limit ? chars.slice(0, limit - 1).join("") + "…" : label
    var figures = cpuText(usage)
    if (showMemory) {
      var memory = typeof usage.memUsed === "number" && isFinite(usage.memUsed) && usage.memUsed >= 0
        && typeof usage.memTotal === "number" && isFinite(usage.memTotal) && usage.memTotal > 0
        ? Math.round(Math.min(1, usage.memUsed / usage.memTotal) * 100) + "%" : "–"
      figures = "c:" + figures + " r:" + memory
    }
    parts.push((showNames === false ? "" : short + " ") + figures)
  }
  if (more > 0) parts.push("+" + more)
  return parts.join(" · ")
}

function barText(icon, count, showLabel, statsText) {
  var parts = [icon]
  if (showLabel) parts.push(count)
  if (statsText !== "") parts.push(statsText)
  return parts.join("  ")
}

// settingsError first: the user just caused it, by hand.
function errorText(settingsError, lastError, actionError) {
  if (settingsError !== "") return settingsError
  return lastError !== "" ? lastError : actionError
}

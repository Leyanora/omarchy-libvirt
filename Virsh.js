// virsh argv, the poll script, and the parsers for what comes back.
// Pure: nothing here touches QML, and nothing here holds state.

// Names reach virsh as argv; shq() covers the two scripts and the host-run templates.
function shq(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// A `d:` prefix, so a domain named `constructor` or `__proto__` cannot read as live.
function key(name) {
  return "d:" + name
}

// JSON, not a joined string: ("a b", "") must not collide with ("a", "b").
function armKey(verb, domain, snapshot) {
  return JSON.stringify([verb, domain, snapshot || ""])
}

// Allowlist: actionArgv builds argv from nothing else.
var ACTION_VERBS = [
  "start", "resume", "shutdown", "destroy",
  "suspend", "reboot", "managedsave", "managedsave-remove"
]

// Column 0 tags each line (R/P/A/M/E) so names with spaces parse. Never exits nonzero.
function pollScript(uri) {
  return [
    "u=" + shq(uri),
    "command -v virsh >/dev/null 2>&1 || { echo 'E virsh is not installed'; exit 0; }",
    "all=$(virsh -c \"$u\" -q list --all --name 2>&1)",
    "if [ $? -ne 0 ]; then",
    "  printf 'E %s\\n' \"$(printf '%s' \"$all\" | tr '\\n' ' ')\"",
    "  exit 0",
    "fi",
    "virsh -c \"$u\" -q list --name --state-running 2>/dev/null | sed '/^$/d;s/^/R /'",
    "virsh -c \"$u\" -q list --name --state-paused 2>/dev/null | sed '/^$/d;s/^/P /'",
    // --all is required: `list` defaults to active, a saved domain never is.
    "virsh -c \"$u\" -q list --all --name --with-managed-save 2>/dev/null | sed '/^$/d;s/^/M /'",
    "printf '%s\\n' \"$all\" | sed '/^$/d;s/^/A /'"
  ].join("\n")
}

// Returns { error, domains, running, paused }; the caller decides what to assign.
function parsePoll(text) {
  var running = ({})
  var paused = ({})
  var saved = ({})
  var names = []
  var error = ""

  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.length < 2) continue
    var value = line.substring(2)
    switch (line.charAt(0)) {
      case "E": error = value; break
      case "R": running[key(value)] = true; break
      case "P": paused[key(value)] = true; break
      case "M": saved[key(value)] = true; break
      case "A": names.push(value); break
    }
  }

  if (error !== "")
    return { error: error, domains: [], running: running, paused: paused }

  var list = []
  for (var j = 0; j < names.length; j++) {
    var name = names[j]
    list.push({
      name: name,
      domainState: running[key(name)] ? "running" : (paused[key(name)] ? "paused" : "shut off"),
      saved: !!saved[key(name)]
    })
  }
  // By name only, never by state: a row must not move when its domain does.
  list.sort(function (a, b) {
    return a.name.localeCompare(b.name)
  })

  return { error: "", domains: list, running: running, paused: paused }
}

// True when two poll results render identically, so `domains` is not reassigned.
// A JS-array model rebuilds every delegate on assignment; without this the list
// churned on every tick and no row-level animation could survive a poll.
function sameDomains(a, b) {
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (a[i].name !== b[i].name) return false
    if (a[i].domainState !== b[i].domainState) return false
    if (a[i].saved !== b[i].saved) return false
  }
  return true
}

// Case-insensitive substring over the already-polled list; no virsh call.
function filterDomains(domains, query) {
  var needle = String(query === undefined || query === null ? "" : query).trim().toLowerCase()
  if (needle === "") return domains
  var out = []
  for (var i = 0; i < domains.length; i++)
    if (String(domains[i].name).toLowerCase().indexOf(needle) >= 0) out.push(domains[i])
  return out
}

// Empty lines dropped, nothing else: revert/delete must match libvirt exactly.
function parseSnapshotList(text) {
  var found = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i] !== "") found.push(lines[i])
  return found
}

// virsh banners the useful line last.
function lastLine(text) {
  var lines = String(text || "").trim().split("\n")
  return lines[lines.length - 1]
}

// Typed input only — names from snapshot-list must pass through untouched.
function cleanSnapshotName(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^[\s\/]+|[\s\/]+$/g, "")
    .replace(/[\s\/]+/g, "-")
    .replace(/^\.+/, "")
}

// null for anything off the allowlist, so a bad verb cannot reach a Process.
function actionArgv(uri, verb, domain) {
  if (domain === "" || ACTION_VERBS.indexOf(verb) < 0) return null
  return ["virsh", "-c", uri, verb, domain]
}

function snapshotListArgv(uri, domain) {
  return ["virsh", "-c", uri, "-q", "snapshot-list", domain, "--name"]
}

function snapshotCreateArgv(uri, domain, name, description) {
  var argv = ["virsh", "-c", uri, "snapshot-create-as", "--domain", domain]
  var clean = cleanSnapshotName(name)
  // Empty, or sanitised away to nothing, gets libvirt's automatic name.
  if (clean !== "") argv = argv.concat(["--name", clean])
  // Free text libvirt stores verbatim, so it is passed through uncleaned.
  var note = String(description === undefined || description === null ? "" : description).trim()
  return note === "" ? argv : argv.concat(["--description", note])
}

function snapshotCurrentArgv(uri, domain) {
  return ["virsh", "-c", uri, "-q", "snapshot-current", domain, "--name"]
}

// One line, or virsh's error on stderr — which never reaches this parser.
function parseSnapshotCurrent(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i] !== "") return lines[i]
  return ""
}

function domInfoArgv(uri, domain) {
  return ["virsh", "-c", uri, "dominfo", domain]
}

function domStateArgv(uri, domain) {
  return ["virsh", "-c", uri, "domstate", domain, "--reason"]
}

// dominfo is a `Field: value` table; only the two fields the row renders are kept.
function parseDomInfo(text) {
  var detail = { cpus: 0, memory: "" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var at = lines[i].indexOf(":")
    if (at < 0) continue
    var field = lines[i].substring(0, at).trim()
    var value = lines[i].substring(at + 1).trim()
    if (field === "CPU(s)") detail.cpus = parseInt(value, 10) || 0
    else if (field === "Max memory") detail.memory = formatKiB(parseInt(value, 10))
  }
  return detail
}

// `shut off (destroyed)` — the reason in parentheses is the half worth showing, and
// libvirt says `unknown` whenever it has none, which is worth less than a blank.
function parseDomState(text) {
  var found = /\(([^)]*)\)\s*$/.exec(lastLine(text))
  var reason = found ? found[1] : ""
  return reason === "unknown" ? "" : reason
}

// libvirt reports memory in KiB; a row has no space for seven digits of it.
function formatKiB(kib) {
  var mib = Number(kib) / 1024
  if (!(mib > 0)) return ""
  if (mib >= 1024) return (Math.round(mib / 102.4) / 10) + " GiB"
  return Math.round(mib) + " MiB"
}

function snapshotRevertArgv(uri, domain, name) {
  return ["virsh", "-c", uri, "snapshot-revert", domain, name]
}

function snapshotDeleteArgv(uri, domain, name) {
  return ["virsh", "-c", uri, "snapshot-delete", domain, name]
}

// The host runs these through its own `bash -lc`, so both halves need shq().
function expandTemplate(template, uri, name) {
  return String(template)
    .replace(/\{uri\}/g, function () { return shq(uri) })
    .replace(/\{name\}/g, function () { return shq(name) })
}

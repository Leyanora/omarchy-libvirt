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

function snapshotCreateArgv(uri, domain, name) {
  var argv = ["virsh", "-c", uri, "snapshot-create-as", "--domain", domain]
  var clean = cleanSnapshotName(name)
  // Empty, or sanitised away to nothing, gets libvirt's automatic name.
  return clean === "" ? argv : argv.concat(["--name", clean])
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

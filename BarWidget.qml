import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// libvirt domains in the bar, driven entirely through `virsh`.
BarWidget {
  id: root
  moduleName: "leyanora.libvirt"

  // ---- Settings -------------------------------------------------------
  readonly property string configuredUri: setting("uri", "qemu:///session")
  readonly property string configuredIcon: setting("icon", "󰒋")
  readonly property int configuredInterval: Math.max(2, setting("interval", 10))
  readonly property bool configuredShowCount: setting("showCount", false)
  readonly property bool configuredConfirmForceOff: setting("confirmForceOff", true)
  readonly property bool configuredConfirmDiscardSaved: setting("confirmDiscardSaved", true)
  readonly property bool configuredConfirmSnapshotRevert: setting("confirmSnapshotRevert", true)
  readonly property bool configuredShowSnapshots: setting("showSnapshots", true)
  readonly property int configuredAddressWindow: Math.max(10, setting("addressWindow", 120))
  // Floored, not theme-pure: a sharp theme would otherwise render every corner square.
  readonly property int configuredRadius: setting("cornerRadius", Math.max(Style.cornerRadius, Style.space(6)))
  readonly property string configuredManager: setting("manager", "virt-manager -c " + shq(configuredUri))
  readonly property string configuredOnRightClick: setting("onRightClick", configuredManager)

  readonly property string configuredConsole: setting("console", "virt-viewer --connect {uri} {name}")

  readonly property bool configuredSuppressCrashToasts: setting("suppressCrashToasts", false)
  readonly property string configuredCrashIgnore: setting("crashIgnore", "^qemu-system-")

  // The one sanctioned hardcode: a state light must read green/red.
  readonly property string defaultColorRunning: "#3fb950"
  readonly property string defaultColorPaused: "#d29922"
  readonly property string defaultColorStopped: "#f85149"

  readonly property string colorRunningHex: String(setting("colorRunning", defaultColorRunning))
  readonly property string colorPausedHex: String(setting("colorPaused", defaultColorPaused))
  readonly property string colorStoppedHex: String(setting("colorStopped", defaultColorStopped))

  readonly property color colorRunning: colorRunningHex
  readonly property color colorPaused: colorPausedHex
  readonly property color colorStopped: colorStoppedHex

  // ---- State ----------------------------------------------------------
  property var domains: []

  property string lastError: ""
  property string actionError: ""
  property bool busy: false

  property string busyDomain: ""

  // armedDomain/armedVerb: the split halves, so a poll can disarm without parsing.
  property string armedAction: ""
  property string armedDomain: ""
  property string armedVerb: ""

  property var details: ({})

  property string expandedDomain: ""
  property string snapshotDomain: ""
  property bool settingsOpen: false

  // Neither sub-view: list-view elements gate on this, not on the sub-views.
  readonly property bool listView: snapshotDomain === "" && !settingsOpen

  readonly property int runningCount: countState("running")
  readonly property int totalCount: domains.length

  readonly property bool connectionDown: lastError !== ""

  readonly property string connectionLabel: connectionDown ? "Disconnected" : "Connected"

  readonly property string displayText: runningCount > 0 ? String(runningCount) : ""
  readonly property bool showLabel: !vertical && configuredShowCount && displayText !== ""

  readonly property string summary: lastError !== ""
    ? lastError
    : (totalCount === 0
      ? "No domains on " + configuredUri
      : runningCount + " of " + totalCount + " running")

  // ---- Popup lifecycle -------------------------------------------------
  // opened/open()/close() are how the shell routes summon/hide/toggle — keep the names.
  property bool popupOpen: false

  readonly property bool opened: popupOpen

  function open() {
    popupOpen = true
    refresh()
  }

  function close() {
    popupOpen = false
    clearArm()
    expandedDomain = ""
    snapshotDomain = ""
    settingsOpen = false
  }

  function togglePanel() {
    if (popupOpen) close()
    else open()
  }

  // ---- Helpers ---------------------------------------------------------
  // Names reach virsh as argv; shq() covers the two scripts and the host-run templates.
  function shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function key(name) {
    return "d:" + name
  }

  // JSON, not a joined string: ("a b", "") must not collide with ("a", "b").
  function armKey(verb, domain, snapshot) {
    return JSON.stringify([verb, domain, snapshot || ""])
  }

  function isArmed(verb, domain, snapshot) {
    return armedAction !== "" && armedAction === armKey(verb, domain, snapshot)
  }

  function arm(verb, domain, snapshot) {
    armedAction = armKey(verb, domain, snapshot)
    armedDomain = domain
    armedVerb = verb
    disarm.restart()
  }

  function clearArm() {
    disarm.stop()
    armedAction = ""
    armedDomain = ""
    armedVerb = ""
  }

  function confirmed(verb, domain, snapshot, confirm) {
    if (!confirm) return true
    if (isArmed(verb, domain, snapshot)) {
      clearArm()
      return true
    }
    arm(verb, domain, snapshot)
    return false
  }

  function countState(state) {
    var found = 0
    for (var i = 0; i < domains.length; i++)
      if (domains[i].domainState === state) found++
    return found
  }

  function refresh() {
    poll.running = false
    poll.running = true
  }

  // ---- Polling ---------------------------------------------------------
  // Column 0 tags each line (R/P/A/M/E) so names with spaces parse. Never exits nonzero.
  readonly property string pollScript: [
    "u=" + shq(configuredUri),
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

  function applyPoll(text) {
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

    lastError = error
    if (error !== "") {
      domains = []
      details = ({})
      addresses = ({})
      addressTries = ({})
      clearArm()
      expandedDomain = ""
      snapshotDomain = ""
      return
    }

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

    domains = list

    // Disarm once the button being confirmed against is gone.
    if (armedDomain !== "") {
      var defined = false
      for (var k = 0; k < list.length; k++)
        if (list[k].name === armedDomain) defined = true
      var live = !!running[key(armedDomain)] || !!paused[key(armedDomain)]
      if (!defined || (armedVerb === "destroy" && !live))
        clearArm()
    }

    // dominfo survives a stop; an address does not, which is what re-reads the lease.
    var kept = ({})
    var keptAddresses = ({})
    var keptTries = ({})
    for (var m = 0; m < list.length; m++) {
      var cached = details[key(list[m].name)]
      if (cached !== undefined) kept[key(list[m].name)] = cached
      if (list[m].domainState !== "running") continue
      // A stop drops the address and the budget with it, so a restart looks again.
      var address = addresses[key(list[m].name)]
      if (address !== undefined) keptAddresses[key(list[m].name)] = address
      var tries = addressTries[key(list[m].name)]
      if (tries !== undefined) keptTries[key(list[m].name)] = tries
    }
    details = kept
    addresses = keptAddresses
    addressTries = keptTries

    if (expandedDomain !== "") {
      if (details[key(expandedDomain)] === undefined) fetchDetail(expandedDomain)
      if (addressWanted(expandedDomain) && running[key(expandedDomain)])
        fetchAddress(expandedDomain)
    }
  }

  // No `-l`, no BASH_ENV: a startup file's output would parse as a poll record.
  Process {
    id: poll
    command: ["env", "-u", "BASH_ENV", "bash", "-c", root.pollScript]
    stdout: StdioCollector {
      onStreamFinished: root.applyPoll(text)
    }
  }

  Timer {
    running: true
    interval: root.configuredInterval * 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- Actions ---------------------------------------------------------
  // One at a time, argv never a shell string. virsh returns when queued — hence settle.
  property var actionCommand: []

  // Allowlist: runAction builds argv from nothing else.
  readonly property var actionVerbs: [
    "start", "resume", "shutdown", "destroy",
    "suspend", "reboot", "managedsave", "managedsave-remove"
  ]

  function runAction(verb, domain) {
    if (domain === "" || actionVerbs.indexOf(verb) < 0) return
    runCommand(["virsh", "-c", configuredUri, verb, domain], domain)
  }

  // Prebuilt argv for the verbs that need flags; never sourced from a setting.
  function runCommand(argv, domain) {
    if (busy) return
    actionError = ""
    clearArm()
    actionCommand = argv
    busy = true
    busyDomain = domain
    action.running = true
  }

  function openConsole(domain) {
    if (configuredConsole === "" || domain === "" || !bar) return
    var command = configuredConsole
      .replace(/\{uri\}/g, function () { return root.shq(root.configuredUri) })
      .replace(/\{name\}/g, function () { return root.shq(domain) })
    bar.run(command)
    close()
  }

  // argv, not `printf | wl-copy` through a shell: the value stays one argument.
  property string copiedValue: ""

  function copyToClipboard(value) {
    if (value === "") return
    Quickshell.execDetached(["wl-copy", "--", value])
    copiedValue = value
    copied.restart()
  }

  Timer {
    id: copied
    interval: 1500
    onTriggered: root.copiedValue = ""
  }

  function forceOff(domain) {
    if (confirmed("destroy", domain, "", configuredConfirmForceOff))
      runAction("destroy", domain)
  }

  function discardSaved(domain) {
    if (confirmed("managedsave-remove", domain, "", configuredConfirmDiscardSaved))
      runAction("managedsave-remove", domain)
  }

  Process {
    id: action
    command: root.actionCommand
    stdout: StdioCollector {}  // dropped; the popup shows state, not chatter
    stderr: StdioCollector {
      // virsh banners the useful line last.
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        root.actionError = lines[lines.length - 1]
      }
    }
    onExited: function (exitCode, exitStatus) {
      root.busy = false
      root.busyDomain = ""
      if (exitCode === 0) root.actionError = ""
      settle.ticks = 0
      settle.restart()
      root.refresh()
      if (root.snapshotDomain !== "") root.fetchSnapshots(root.snapshotDomain)
    }
  }

  Timer {
    id: settle
    property int ticks: 0
    interval: 1200
    repeat: true
    onTriggered: {
      root.refresh()
      ticks++
      if (ticks >= 3) {
        ticks = 0
        stop()
      }
    }
  }

  Timer {
    id: disarm
    interval: 4000
    onTriggered: root.clearArm()
  }

  // ---- Domain detail ---------------------------------------------------
  // Own Process, deliberately not gated on `busy`: a read must not queue behind an action.
  property var detailCommand: []
  property string detailDomain: ""

  function fetchDetail(domain) {
    if (domain === "" || detail.running) return
    detailDomain = domain
    detailCommand = ["virsh", "-c", configuredUri, "-q", "dominfo", domain]
    detail.running = true
  }

  // "CPU(s): 4" + "Max memory: 8388608 KiB" -> "4 vCPU  ·  8 GiB"
  function applyDetail(text) {
    if (detailDomain === "") return

    var cpus = ""
    var memory = ""

    // No tag to strip: with argv, every line here is virsh's own.
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var field = lines[i]
      var split = field.indexOf(":")
      if (split < 0) continue
      var label = field.substring(0, split).trim()
      var value = field.substring(split + 1).trim()
      if (label === "CPU(s)") cpus = value
      else if (label === "Max memory") memory = value
    }

    var parts = []
    if (cpus !== "") parts.push(cpus + " vCPU")
    var kib = parseInt(memory, 10)
    if (!isNaN(kib) && kib > 0)
      parts.push(kib >= 1048576
        ? (Math.round(kib / 104857.6) / 10) + " GiB"
        : Math.round(kib / 1024) + " MiB")

    var next = ({})
    for (var existing in details) next[existing] = details[existing]
    next[key(detailDomain)] = parts.join("  ·  ")
    details = next
  }

  // ---- Guest address ---------------------------------------------------
  // Not static like dominfo: a lease lands late, so it is dropped when a domain stops.
  property var addresses: ({})
  property var addressCommand: []
  property string addressDomain: ""

  // Completed rounds per domain; a round walks every source once.
  property var addressTries: ({})

  // Budgeted in seconds, not rounds: interval is user-settable from 2s up.
  readonly property int addressTryLimit: Math.max(3, Math.ceil(configuredAddressWindow / configuredInterval))

  // In order: managed network, guest agent (all qemu:///session has), then bridged.
  readonly property var addressSources: ["lease", "agent", "arp"]
  property int addressSourceIndex: 0

  function fetchAddress(domain) {
    if (domain === "" || addressLookup.running) return
    addressDomain = domain
    addressSourceIndex = 0
    runAddressSource()
  }

  // True while a domain still has retry budget left and no address yet.
  function addressWanted(domain) {
    return domain !== "" && addresses[key(domain)] === undefined
      && (addressTries[key(domain)] || 0) < addressTryLimit
  }

  function runAddressSource() {
    addressCommand = ["virsh", "-c", configuredUri, "-q", "domifaddr",
                      addressDomain, "--source", addressSources[addressSourceIndex]]
    addressLookup.running = true
    addressWatchdog.restart()
  }

  function storeAddress(domain, value) {
    var next = ({})
    for (var existing in addresses) next[existing] = addresses[existing]
    next[key(domain)] = value
    addresses = next
  }

  function countAddressTry(domain) {
    var next = ({})
    for (var existing in addressTries) next[existing] = addressTries[existing]
    next[key(domain)] = (addressTries[key(domain)] || 0) + 1
    addressTries = next
  }

  function resetAddressTries(domain) {
    var next = ({})
    for (var existing in addressTries) next[existing] = addressTries[existing]
    delete next[key(domain)]
    addressTries = next
  }

  // A link-local means DHCP never completed — treating it as found ends the retry.
  function usableAddress(ip) {
    return ip !== "0.0.0.0" && ip.indexOf("127.") !== 0 && ip.indexOf("169.254.") !== 0
  }

  // First usable IPv4 anywhere, so the column layout does not matter.
  function parseAddress(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var found = lines[i].match(/\b(\d{1,3}(?:\.\d{1,3}){3})\b/)
      if (found && usableAddress(found[1])) return found[1]
    }
    return ""
  }

  // A connected-but-wedged agent would otherwise block every later lookup.
  Timer {
    id: addressWatchdog
    interval: 10000
    onTriggered: addressLookup.running = false
  }

  Process {
    id: addressLookup
    command: root.addressCommand
    stdout: StdioCollector { id: addressOut }
    stderr: StdioCollector {}
    onExited: function (exitCode, exitStatus) {
      addressWatchdog.stop()
      var found = root.parseAddress(addressOut.text)
      if (found === "" && root.addressSourceIndex < root.addressSources.length - 1) {
        root.addressSourceIndex++
        root.runAddressSource()
        return
      }
      // Nothing found is never final: count the round and let the poll try again.
      if (found === "") root.countAddressTry(root.addressDomain)
      else root.storeAddress(root.addressDomain, found)

      // Another row was expanded mid-flight; that fetch was dropped by the busy guard.
      if (root.expandedDomain !== "" && root.expandedDomain !== root.addressDomain
          && root.addressWanted(root.expandedDomain) && root.domainIsRunning(root.expandedDomain))
        root.fetchAddress(root.expandedDomain)
    }
  }

  Process {
    id: detail
    command: root.detailCommand
    stdout: StdioCollector {
      onStreamFinished: root.applyDetail(text)
    }
    stderr: StdioCollector {}  // a failed read blanks the caption, nothing louder
    onExited: function (exitCode, exitStatus) {
      // A row expanded while this fetch was in flight; catch it up.
      if (root.expandedDomain !== "" && root.details[root.key(root.expandedDomain)] === undefined)
        root.fetchDetail(root.expandedDomain)
    }
  }

  onExpandedDomainChanged: {
    if (expandedDomain === "") return
    if (details[key(expandedDomain)] === undefined) fetchDetail(expandedDomain)
    // Re-expanding is the manual re-check: it hands the domain a fresh budget.
    resetAddressTries(expandedDomain)
    if (addressWanted(expandedDomain) && domainIsRunning(expandedDomain))
      fetchAddress(expandedDomain)
  }

  function domainIsRunning(name) {
    for (var i = 0; i < domains.length; i++)
      if (domains[i].name === name) return domains[i].domainState === "running"
    return false
  }

  // ---- Snapshots -------------------------------------------------------
  property var snapshots: []
  property var snapshotCommand: []

  function fetchSnapshots(domain) {
    if (domain === "") return
    snapshotCommand = ["virsh", "-c", configuredUri, "-q", "snapshot-list", domain, "--name"]
    snapshotList.running = false
    snapshotList.running = true
  }

  // Empty lines dropped, nothing else: revert/delete must match libvirt exactly.
  function applySnapshots(text) {
    var found = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++)
      if (lines[i] !== "") found.push(lines[i])
    snapshots = found
  }

  Process {
    id: snapshotList
    command: root.snapshotCommand
    stdout: StdioCollector {
      onStreamFinished: root.applySnapshots(text)
    }
    stderr: StdioCollector {}
  }

  // Driven by the property, not openSnapshots(), so no route in leaves a stale list.
  onSnapshotDomainChanged: {
    snapshots = []
    if (snapshotDomain !== "") fetchSnapshots(snapshotDomain)
  }

  function openSnapshots(domain) {
    clearArm()
    settingsOpen = false
    snapshotDomain = domain
  }

  function closeSnapshots() {
    clearArm()
    snapshotDomain = ""
  }

  // Typed input only — names from snapshot-list must pass through untouched.
  function cleanSnapshotName(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/^[\s\/]+|[\s\/]+$/g, "")
      .replace(/[\s\/]+/g, "-")
      .replace(/^\.+/, "")
  }

  function createSnapshot(domain, name) {
    var clean = cleanSnapshotName(name)
    var argv = ["virsh", "-c", configuredUri, "snapshot-create-as", "--domain", domain]
    // Empty, or sanitised away to nothing, gets libvirt's automatic name.
    if (clean !== "") argv = argv.concat(["--name", clean])
    runCommand(argv, domain)
  }

  function revertSnapshot(domain, name) {
    if (confirmed("snapshot-revert", domain, name, configuredConfirmSnapshotRevert))
      runCommand(["virsh", "-c", configuredUri, "snapshot-revert", domain, name], domain)
  }

  function deleteSnapshot(domain, name) {
    if (confirmed("snapshot-delete", domain, name, configuredConfirmSnapshotRevert))
      runCommand(["virsh", "-c", configuredUri, "snapshot-delete", domain, name], domain)
  }

  // ---- Settings view ---------------------------------------------------
  property string settingsError: ""

  function openSettings() {
    clearArm()
    snapshotDomain = ""
    settingsOpen = true
  }

  function closeSettings() {
    settingsOpen = false
  }

  // The only write to user config, and it replaces the entry wholesale — hence the merge.
  function persistSetting(name, value) {
    var entry = { id: moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    entry[name] = value

    // Local first: throws the switch now, and re-fires the configured* bindings.
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") {
      settingsError = ""
      bar.shell.updateEntryInline(moduleName, entry)
    } else {
      settingsError = "could not save: the shell did not expose updateEntryInline"
    }
  }

  readonly property var colorSettings: [
    { name: "colorRunning", label: "Running" },
    { name: "colorPaused", label: "Paused" },
    { name: "colorStopped", label: "Shut off" }
  ]

  function colorHex(name) {
    return name === "colorRunning" ? colorRunningHex
      : (name === "colorPaused" ? colorPausedHex : colorStoppedHex)
  }

  function colorValue(name) {
    return name === "colorRunning" ? colorRunning
      : (name === "colorPaused" ? colorPaused : colorStopped)
  }

  // Rejected rather than handed to a color property, which reads a bad string as black.
  function isColorHex(value) {
    return /^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(String(value).trim())
  }

  function persistColor(name, value) {
    var clean = String(value).trim()
    if (!isColorHex(clean)) {
      settingsError = "not a colour: use #rgb, #rrggbb or #aarrggbb"
      return false
    }
    settingsError = ""
    persistSetting(name, clean)
    return true
  }

  // ---- Crash toast suppression ----------------------------------------
  // Four load-bearing constraints: flock, content compare, marker line, runtime dir.
  property string crashToggleError: ""

  // Built at call time, never bound: a handler runs before siblings re-evaluate.
  property string crashToggleScript: ""

  function buildCrashToggleScript() {
    return [
    "set -u",
    "umask 077",  // owner-only, rather than leaning on the runtime dir's 0700
    "unit=omarchy-crash-watch.service",
    // Probed on disk, not with `systemctl cat`: that exits 1 from Process.
    "found=0",
    "for d in /usr/lib/systemd/user /etc/systemd/user \"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user\"; do",
    "  [ -f \"$d/$unit\" ] && found=1",
    "done",
    "[ \"$found\" = 1 ] || exit 0",
    "runtime=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"",
    "dir=\"$runtime/systemd/user/$unit.d\"",
    "file=\"$dir/50-" + moduleName + ".conf\"",
    // Swept every reconcile so an upgrade from <=1.0.1 cleans up after itself.
    "legacy=\"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit.d/50-" + moduleName + ".conf\"",
    "marker='# Managed by the " + moduleName + " Omarchy plugin'",
    "lock=\"$runtime/" + moduleName + ".crash-toggle.lock\"",
    "exec 9>\"$lock\" || exit 0",
    "flock 9 || exit 0",
    "want=" + (configuredSuppressCrashToasts ? "1" : "0"),
    // `%` starts a systemd specifier in Environment=; `%%` is the literal.
    "pattern=" + shq(String(configuredCrashIgnore).replace(/%/g, "%%")),
    "changed=0",
    "if [ -f \"$legacy\" ] && grep -qF \"$marker\" \"$legacy\"; then",
    "  rm -f \"$legacy\" || exit 1",
    "  rmdir \"$(dirname \"$legacy\")\" 2>/dev/null || true",
    "  changed=1",
    "fi",
    "if [ \"$want\" = 1 ]; then",
    "  desired=\"$marker",
    "[Service]",
    "Environment=\\\"OMARCHY_CRASH_IGNORE=$pattern\\\"\"",
    "  if [ ! -f \"$file\" ] || [ \"$(cat \"$file\")\" != \"$desired\" ]; then",
    "    mkdir -p \"$dir\" || exit 1",
    "    printf '%s\\n' \"$desired\" >\"$file.tmp\" && mv \"$file.tmp\" \"$file\" || exit 1",
    "    changed=1",
    "  fi",
    "elif [ -f \"$file\" ] && grep -qF \"$marker\" \"$file\"; then",
    "  rm -f \"$file\" || exit 1",
    "  changed=1",
    "fi",
    "[ \"$changed\" = 1 ] || exit 0",
    "systemctl --user daemon-reload || exit 1",
    "systemctl --user restart \"$unit\" || exit 1"
    ].join("\n")
  }

  // `settings` is injected after construction, so onCompleted sees defaults; queue.
  property bool crashTogglePending: false

  function reconcileCrashToasts() {
    // Quote, newline or trailing backslash all break the Environment= value.
    if (/["\n]|\\$/.test(configuredCrashIgnore)) {
      crashToggleError = "crashIgnore cannot contain quotes or newlines, or end in a backslash"
      return
    }
    crashToggleError = ""
    if (crashToggle.running) {
      crashTogglePending = true
      return
    }
    crashTogglePending = false
    crashToggleScript = buildCrashToggleScript()
    crashToggle.running = true
  }

  Component.onCompleted: reconcileCrashToasts()
  onConfiguredSuppressCrashToastsChanged: reconcileCrashToasts()
  onConfiguredCrashIgnoreChanged: reconcileCrashToasts()

  Process {
    id: crashToggle
    command: ["env", "-u", "BASH_ENV", "bash", "-c", root.crashToggleScript]
    stderr: StdioCollector {
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.crashToggleError = message.split("\n").pop()
      }
    }
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && root.crashToggleError === "")
        root.crashToggleError = "could not update the crash-watch drop-in"
      if (root.crashTogglePending) {
        root.crashTogglePending = false
        root.reconcileCrashToasts()
      }
    }
  }

  // ---- Bar button ------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showLabel ? (root.configuredIcon + "  " + root.displayText) : root.configuredIcon
    active: root.popupOpen
    useActiveColor: false
    dimmed: root.runningCount === 0
    tooltipText: root.summary
    fixedWidth: root.vertical ? root.barSize : -1
    fixedHeight: root.vertical ? root.barSize : -1

    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.configuredOnRightClick !== "" && root.bar)
          root.bar.run(root.configuredOnRightClick)
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        root.refresh()
        return
      }
      root.togglePanel()
    }

    onWheelMoved: function (delta) {
      root.refresh()
    }
  }

  // ---- Action chip -----------------------------------------------------
  // Icon plus label: PanelActionButton is icon-only and the host Ui tree is read-only.
  component ActionChip: BorderSurface {
    id: chip

    property string iconText: ""
    property string label: ""
    property color foreground: Color.foreground
    property color hoverColor: foreground
    property string fontFamily: Style.font.family
    // Armed half of arm-then-confirm: the chip wears the urgent colour and a border.
    property bool accented: false

    signal clicked()

    implicitHeight: Math.max(Style.space(26), Style.font.icon + Style.spacing.md * 2)
    radius: height / 2

    readonly property bool hot: chipMouse.containsMouse && chip.enabled
    readonly property color tint: accented ? hoverColor : foreground

    color: hot ? Style.hoverFillFor(hoverColor, hoverColor) : Style.normalFillFor(foreground, Color.accent)
    borderSpec: Border.controlSpec(hot || accented ? "hover-cursor" : "normal", tint, Color.accent)

    Behavior on color { ColorAnimation { duration: 60 } }

    Row {
      id: chipRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.md + chip.borderLeft
      anchors.rightMargin: Style.spacing.sm + chip.borderRight
      spacing: Style.spacing.xs

      Text {
        id: chipIcon
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.iconText
        color: chip.enabled ? chip.tint : Qt.darker(chip.foreground, 2.0)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: chipRow.width - chipIcon.width - chipRow.spacing
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: chip.label
        color: chip.enabled ? chip.tint : Qt.darker(chip.foreground, 2.0)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.enabled
      cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: chip.clicked()
    }
  }

  // ---- Popup -----------------------------------------------------------
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // Wider in settings: Toggle elides its label and never wraps it.
    contentWidth: popup.fittedContentWidth(Style.space(root.settingsOpen ? 400 : 340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property color foreground: root.bar ? root.bar.foreground : Color.popups.text
    readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.spacing.sm

      Item {
        width: parent.width
        implicitHeight: Math.max(title.implicitHeight, headerActions.implicitHeight)

        PanelActionButton {
          id: backButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.listView
          iconText: "󰅁"
          tooltipText: "Back"
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          onClicked: {
            if (root.settingsOpen) root.closeSettings()
            else root.closeSnapshots()
          }
        }

        // PlainText on every Text: AutoText would parse `<` in a domain name as markup.
        Text {
          id: title
          anchors.left: backButton.visible ? backButton.right : parent.left
          anchors.leftMargin: backButton.visible ? Style.spacing.xs : 0
          anchors.right: headerActions.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.settingsOpen
            ? "Settings"
            : (root.snapshotDomain !== "" ? root.snapshotDomain : "Virtual machines")
          color: Color.popups.text
          font.family: popup.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        // A Row skips invisible children, so hidden buttons leave no gap.
        Row {
          id: headerActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.listView
            iconText: "󰒓"
            tooltipText: "Settings"
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            onClicked: root.openSettings()
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.settingsOpen
            iconText: "󰑓"
            tooltipText: "Refresh"
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            enabled: !root.busy
            onClicked: {
              if (root.snapshotDomain !== "") root.fetchSnapshots(root.snapshotDomain)
              else root.refresh()
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.listView
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.connectionLabel
        color: root.connectionDown ? popup.urgent : Qt.darker(Color.popups.text, 1.4)
        font.family: popup.fontFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: connectionMouse
          anchors.fill: parent
          hoverEnabled: true

          PanelToolTip {
            visible: connectionMouse.containsMouse
            text: root.configuredUri
            fontFamily: popup.fontFamily
          }
        }
      }

      Text {
        width: parent.width
        visible: root.snapshotDomain !== ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "Snapshots"
        color: Qt.darker(Color.popups.text, 1.4)
        font.family: popup.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator {
        foreground: popup.foreground
      }

      ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, Style.space(300))
        visible: root.domains.length > 0 && root.listView
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: root.domains

        delegate: Item {
          id: row
          required property var modelData

          readonly property string domainName: row.modelData.name
          readonly property string domainState: row.modelData.domainState
          readonly property bool isRunning: row.domainState === "running"
          readonly property bool isPaused: row.domainState === "paused"
          readonly property bool isOff: !isRunning && !isPaused
          readonly property bool isSaved: row.modelData.saved === true && row.isOff
          readonly property bool armedForceOff: root.isArmed("destroy", row.domainName, "")
          readonly property bool armedDiscard: root.isArmed("managedsave-remove", row.domainName, "")
          readonly property bool working: root.busy && root.busyDomain === row.domainName
          readonly property bool expanded: root.expandedDomain === row.domainName

          width: list.width
          height: frame.height

          // The border is what makes an expanded row read as one object.
          BorderSurface {
            id: frame
            width: parent.width
            // The pane's own top margin is in the sum too, or the bottom edge clips.
            height: header.height + (row.expanded
              ? detailPane.height + Style.spacing.xs + Style.spacing.sm + frame.borderTop * 2
              : 0)
            radius: root.configuredRadius
            color: "transparent"
            borderSpec: row.expanded
              ? Border.flat(Qt.darker(popup.foreground, 1.8), Math.max(1, Style.space(1)))
              : Border.none()

            // Hover fill belongs to the header, not the whole delegate.
            Rectangle {
              id: header
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: frame.borderTop
              height: Style.space(30)
              radius: root.configuredRadius
              color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: width / 2
                // Hollow, not a fourth colour: a saved domain is still shut off.
                color: row.isSaved
                  ? "transparent"
                  : (row.isRunning ? root.colorRunning : (row.isPaused ? root.colorPaused : root.colorStopped))
                border.width: row.isSaved ? Math.max(1, Style.space(2)) : 0
                border.color: root.colorStopped
                visible: !row.working
              }

              Text {
                anchors.centerIn: dot
                visible: row.working
                textFormat: Text.PlainText
                text: "󰇙"
                color: Color.accent
                font.family: popup.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.left: dot.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: actions.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: row.domainName
                color: nameMouse.containsMouse ? Color.accent : Color.popups.text
                opacity: row.isOff ? 0.6 : 1.0
                font.family: popup.fontFamily
                font.pixelSize: Style.font.body
                font.underline: nameMouse.containsMouse

                MouseArea {
                  id: nameMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !row.isOff && root.configuredConsole !== ""
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openConsole(row.domainName)

                  PanelToolTip {
                    visible: nameMouse.containsMouse
                    text: "Open console"
                    fontFamily: popup.fontFamily
                  }
                }
              }

              Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                PanelActionButton {
                  visible: row.isOff
                  iconText: row.isSaved ? "󰦛" : "󰐊"
                  tooltipText: row.isSaved ? "Restore" : "Start"
                  foreground: popup.foreground
                  fontFamily: popup.fontFamily
                  enabled: !root.busy
                  onClicked: root.runAction("start", row.domainName)
                }

                PanelActionButton {
                  visible: row.isPaused
                  iconText: "󰐊"
                  tooltipText: "Resume"
                  foreground: popup.foreground
                  fontFamily: popup.fontFamily
                  enabled: !root.busy
                  onClicked: root.runAction("resume", row.domainName)
                }

                PanelActionButton {
                  visible: row.isRunning
                  iconText: "󰓛"
                  tooltipText: "Shut down"
                  foreground: popup.foreground
                  fontFamily: popup.fontFamily
                  enabled: !root.busy
                  onClicked: root.runAction("shutdown", row.domainName)
                }

                PanelActionButton {
                  visible: !row.isOff
                  iconText: "󱐋"
                  tooltipText: row.armedForceOff ? "Click again to force off" : "Force off"
                  foreground: row.armedForceOff ? popup.urgent : popup.foreground
                  hoverColor: popup.urgent
                  bordered: row.armedForceOff
                  fontFamily: popup.fontFamily
                  enabled: !root.busy
                  onClicked: root.forceOff(row.domainName)
                }

                PanelActionButton {
                  iconText: row.expanded ? "󰅃" : "󰅀"
                  tooltipText: row.expanded ? "Less" : "More"
                  foreground: popup.foreground
                  fontFamily: popup.fontFamily
                  onClicked: root.expandedDomain = row.expanded ? "" : row.domainName
                }
              }
            }

            // ---- Expanded detail ----------------------------------------
            // Filled like Toggle at rest, so an open row reads as one settings-style card.
            BorderSurface {
              id: detailPane
              anchors.top: header.bottom
              anchors.topMargin: Style.spacing.xs
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.spacing.sm + frame.borderLeft
              anchors.rightMargin: Style.spacing.sm + frame.borderRight
              visible: row.expanded
              height: detailContent.implicitHeight + Style.spacing.sm * 2
              radius: root.configuredRadius
              color: Style.normalFillFor(popup.foreground, Color.accent)

              Column {
                id: detailContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.spacing.sm
                spacing: Style.spacing.xs

                // The address is its own item so only it is clickable; "" means none found.
                Row {
                  id: detailLine
                  width: parent.width
                  spacing: 0

                  readonly property string spec: root.details[root.key(row.domainName)] || ""
                  readonly property string address: row.isRunning
                    ? (root.addresses[root.key(row.domainName)] || "")
                    : ""

                  // Only `address` is a real IP; a placeholder must never reach the copy path.
                  readonly property string addressText: !row.isRunning ? ""
                    : address !== "" ? address
                    : (root.addressTries[root.key(row.domainName)] || 0) >= root.addressTryLimit
                      ? "no address" : "looking up…"

                  Text {
                    textFormat: Text.PlainText
                    text: detailLine.spec
                    color: Qt.darker(Color.popups.text, 1.4)
                    font.family: popup.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: detailLine.addressText !== "" && detailLine.spec !== ""
                    textFormat: Text.PlainText
                    text: "  ·  "
                    color: Qt.darker(Color.popups.text, 1.4)
                    font.family: popup.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: detailLine.addressText !== ""
                    textFormat: Text.PlainText
                    text: detailLine.addressText
                    color: addressMouse.containsMouse ? Color.accent : Qt.darker(Color.popups.text, 1.4)
                    font.family: popup.fontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: addressMouse.containsMouse

                    MouseArea {
                      id: addressMouse
                      anchors.fill: parent
                      enabled: detailLine.address !== ""
                      hoverEnabled: enabled
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.copyToClipboard(detailLine.address)

                      PanelToolTip {
                        visible: addressMouse.containsMouse
                        text: root.copiedValue === detailLine.address ? "Copied" : "Copy IP"
                        fontFamily: popup.fontFamily
                      }
                    }
                  }
                }

                // Positioners skip invisible children, so this reflows for 1..5 chips.
                Grid {
                  id: chipGrid
                  width: parent.width
                  columns: 2
                  spacing: Style.spacing.xs

                  readonly property real chipWidth: (width - spacing) / 2

                  ActionChip {
                    visible: row.isRunning
                    width: chipGrid.chipWidth
                    iconText: "󰏤"
                    label: "Pause"
                    foreground: popup.foreground
                    fontFamily: popup.fontFamily
                    enabled: !root.busy
                    onClicked: root.runAction("suspend", row.domainName)
                  }

                  ActionChip {
                    visible: row.isRunning
                    width: chipGrid.chipWidth
                    iconText: "󰜉"
                    label: "Reboot"
                    foreground: popup.foreground
                    fontFamily: popup.fontFamily
                    enabled: !root.busy
                    onClicked: root.runAction("reboot", row.domainName)
                  }

                  ActionChip {
                    visible: !row.isOff
                    width: chipGrid.chipWidth
                    iconText: "󰆓"
                    label: "Save state"
                    foreground: popup.foreground
                    fontFamily: popup.fontFamily
                    enabled: !root.busy
                    onClicked: root.runAction("managedsave", row.domainName)
                  }

                  // The label carries the arm state, so no tooltip has to hold a second string.
                  ActionChip {
                    visible: row.isSaved
                    width: chipGrid.chipWidth
                    iconText: "󰆴"
                    label: row.armedDiscard ? "Click again" : "Discard"
                    foreground: popup.foreground
                    hoverColor: popup.urgent
                    accented: row.armedDiscard
                    fontFamily: popup.fontFamily
                    enabled: !root.busy
                    onClicked: root.discardSaved(row.domainName)
                  }

                  ActionChip {
                    visible: root.configuredShowSnapshots
                    width: chipGrid.chipWidth
                    iconText: "󰄄"
                    label: "Snapshots"
                    foreground: popup.foreground
                    fontFamily: popup.fontFamily
                    enabled: !root.busy
                    onClicked: root.openSnapshots(row.domainName)
                  }
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.domains.length === 0 && root.lastError === "" && root.listView
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "No domains defined on this connection."
        color: Color.popups.text
        opacity: 0.7
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Settings view ------------------------------------------------
      // Toggle is stateless: the click writes, the switch follows the binding back.
      Column {
        width: parent.width
        visible: root.settingsOpen
        spacing: Style.spacing.sm

        Toggle {
          width: parent.width
          label: "Suppress qemu crash notifications"
          description: "Also silences a QEMU crash that happens mid-run."
          checked: root.configuredSuppressCrashToasts
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          onClicked: root.persistSetting("suppressCrashToasts", !root.configuredSuppressCrashToasts)
        }

        // Boxed off: three parts of one setting, which a bare hex field would not read as.
        BorderSurface {
          width: parent.width
          height: colorGroup.implicitHeight + Style.spacing.sm * 2
          radius: root.configuredRadius
          color: "transparent"
          borderSpec: Border.flat(Qt.darker(popup.foreground, 1.8), Math.max(1, Style.space(1)))

          Column {
            id: colorGroup
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.spacing.sm
            spacing: Style.spacing.xs

            PanelSectionHeader {
              text: "State light colours"
              foreground: popup.foreground
              fontFamily: popup.fontFamily
            }

            Repeater {
              model: root.colorSettings

              delegate: Item {
                id: colorRow
                required property var modelData

                width: colorGroup.width
                height: Math.max(swatch.height, colorField.implicitHeight)

                Rectangle {
                  id: swatch
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(12)
                  height: width
                  radius: width / 2
                  color: root.colorValue(colorRow.modelData.name)
                }

                Text {
                  id: colorLabel
                  anchors.left: swatch.right
                  anchors.leftMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(64)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: colorRow.modelData.label
                  color: Color.popups.text
                  font.family: popup.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  id: colorField
                  anchors.left: colorLabel.right
                  anchors.leftMargin: Style.spacing.sm
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.colorHex(colorRow.modelData.name)
                  placeholderText: "#rrggbb"
                  foreground: popup.foreground
                  font.family: popup.fontFamily
                  // Typing breaks the binding, so a rejected value is put back by hand.
                  onAccepted: {
                    if (!root.persistColor(colorRow.modelData.name, text))
                      text = root.colorHex(colorRow.modelData.name)
                  }

                  Connections {
                    target: root
                    function onSettingsOpenChanged() {
                      if (root.settingsOpen)
                        colorField.text = root.colorHex(colorRow.modelData.name)
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ---- Snapshot view ------------------------------------------------
      ListView {
        id: snapshotView
        width: parent.width
        height: Math.min(contentHeight, Style.space(220))
        visible: root.snapshotDomain !== "" && root.snapshots.length > 0
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: root.snapshots

        delegate: Rectangle {
          id: snapshotRow
          required property var modelData

          readonly property string snapshotName: String(snapshotRow.modelData)
          readonly property bool armedRevert: root.isArmed("snapshot-revert", root.snapshotDomain, snapshotRow.snapshotName)
          readonly property bool armedDelete: root.isArmed("snapshot-delete", root.snapshotDomain, snapshotRow.snapshotName)

          width: snapshotView.width
          height: Style.space(30)
          radius: root.configuredRadius
          color: snapshotMouse.containsMouse ? Style.hoverFill : "transparent"

          MouseArea {
            id: snapshotMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.right: snapshotActions.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: snapshotRow.snapshotName
            color: Color.popups.text
            font.family: popup.fontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            id: snapshotActions
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: snapshotRow.armedRevert ? "Click again to revert" : "Revert to this snapshot"
              foreground: snapshotRow.armedRevert ? popup.urgent : popup.foreground
              hoverColor: popup.urgent
              bordered: snapshotRow.armedRevert
              fontFamily: popup.fontFamily
              enabled: !root.busy
              onClicked: root.revertSnapshot(root.snapshotDomain, snapshotRow.snapshotName)
            }

            PanelActionButton {
              iconText: "󰆴"
              tooltipText: snapshotRow.armedDelete ? "Click again to delete" : "Delete snapshot"
              foreground: snapshotRow.armedDelete ? popup.urgent : popup.foreground
              hoverColor: popup.urgent
              bordered: snapshotRow.armedDelete
              fontFamily: popup.fontFamily
              enabled: !root.busy
              onClicked: root.deleteSnapshot(root.snapshotDomain, snapshotRow.snapshotName)
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.snapshotDomain !== "" && root.snapshots.length === 0
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "No snapshots for this domain."
        color: Color.popups.text
        opacity: 0.7
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: parent.width
        visible: root.snapshotDomain !== ""
        implicitHeight: Math.max(snapshotName.implicitHeight, createButton.implicitHeight)

        TextField {
          id: snapshotName
          anchors.left: parent.left
          anchors.right: createButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          placeholderText: "New snapshot name"
          enabled: !root.busy
          foreground: popup.foreground
          font.family: popup.fontFamily
          onAccepted: {
            root.createSnapshot(root.snapshotDomain, text)
            text = ""
          }
        }

        PanelActionButton {
          id: createButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰐕"
          tooltipText: "Take snapshot"
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          enabled: !root.busy
          onClicked: {
            root.createSnapshot(root.snapshotDomain, snapshotName.text)
            snapshotName.text = ""
          }
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        // settingsError first: the user just caused it, by hand.
        text: root.settingsError !== ""
          ? root.settingsError
          : (root.lastError !== ""
            ? root.lastError
            : (root.actionError !== "" ? root.actionError : root.crashToggleError))
        color: popup.urgent
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      PanelSeparator {
        visible: root.configuredManager !== "" && root.listView
        foreground: popup.foreground
      }

      Rectangle {
        width: parent.width
        height: Style.space(28)
        radius: root.configuredRadius
        visible: root.configuredManager !== "" && root.listView
        color: managerMouse.containsMouse ? Style.hoverFill : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰍹  Open virt-manager"
          color: Color.popups.text
          font.family: popup.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: managerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.bar) root.bar.run(root.configuredManager)
            root.close()
          }
        }
      }
    }
  }

  // ---- IPC -------------------------------------------------------------
  IpcHandler {
    target: "leyanora.libvirt"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }
}

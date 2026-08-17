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
  readonly property string configuredManager: setting("manager", "virt-manager -c " + shq(configuredUri))
  readonly property string configuredOnRightClick: setting("onRightClick", configuredManager)

  readonly property string configuredConsole: setting("console", "virt-viewer --connect {uri} {name}")

  readonly property bool configuredSuppressCrashToasts: setting("suppressCrashToasts", false)
  readonly property string configuredCrashIgnore: setting("crashIgnore", "^qemu-system-")

  // The file's only hardcoded colors: a state light must read green/red.
  readonly property color colorRunning: setting("colorRunning", "#3fb950")
  readonly property color colorPaused: setting("colorPaused", "#d29922")
  readonly property color colorStopped: setting("colorStopped", "#f85149")

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

  // Neither sub-view. The popup is too narrow to show two at once, so every
  // list-view element gates on this rather than testing the sub-views itself.
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
  // Domain and snapshot names are user-chosen: shq() for shells, key() for lookups.
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

    // Drop cached dominfo for departed domains so a redefined one re-reads.
    var kept = ({})
    for (var m = 0; m < list.length; m++) {
      var cached = details[key(list[m].name)]
      if (cached !== undefined) kept[key(list[m].name)] = cached
    }
    details = kept

    if (expandedDomain !== "" && details[key(expandedDomain)] === undefined)
      fetchDetail(expandedDomain)
  }

  Process {
    id: poll
    command: ["bash", "-lc", root.pollScript]
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
  // One at a time. virsh returns when queued, not when the guest acts — hence settle.
  property string actionScript: ""

  function runAction(verb, domain) {
    if (busy || domain === "") return
    actionError = ""
    clearArm()
    actionScript = "virsh -c " + shq(configuredUri) + " " + verb + " " + shq(domain) + " >/dev/null"
    busy = true
    busyDomain = domain
    action.running = true
  }

  // Prebuilt command for the verbs that need flags; never sourced from a setting.
  function runScript(script, domain) {
    if (busy) return
    actionError = ""
    clearArm()
    actionScript = script
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
    command: ["bash", "-lc", root.actionScript]
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
  property string detailScript: ""
  property string detailDomain: ""

  function buildDetailScript(domain) {
    return "virsh -c " + shq(configuredUri) + " -q dominfo " + shq(domain)
      + " 2>/dev/null | sed 's/^/I /'"
  }

  function fetchDetail(domain) {
    if (domain === "" || detail.running) return
    detailDomain = domain
    detailScript = buildDetailScript(domain)
    detail.running = true
  }

  // "CPU(s): 4" + "Max memory: 8388608 KiB" + "OS Type: hvm" -> "4 vCPU · 8 GiB · hvm"
  function applyDetail(text) {
    if (detailDomain === "") return

    var cpus = ""
    var memory = ""
    var osType = ""

    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].charAt(0) !== "I") continue
      var field = lines[i].substring(2)
      var split = field.indexOf(":")
      if (split < 0) continue
      var label = field.substring(0, split).trim()
      var value = field.substring(split + 1).trim()
      if (label === "CPU(s)") cpus = value
      else if (label === "Max memory") memory = value
      else if (label === "OS Type") osType = value
    }

    var parts = []
    if (cpus !== "") parts.push(cpus + " vCPU")
    var kib = parseInt(memory, 10)
    if (!isNaN(kib) && kib > 0)
      parts.push(kib >= 1048576
        ? (Math.round(kib / 104857.6) / 10) + " GiB"
        : Math.round(kib / 1024) + " MiB")
    if (osType !== "") parts.push(osType)

    var next = ({})
    for (var existing in details) next[existing] = details[existing]
    next[key(detailDomain)] = parts.join("  ·  ")
    details = next
  }

  Process {
    id: detail
    command: ["bash", "-lc", root.detailScript]
    stdout: StdioCollector {
      onStreamFinished: root.applyDetail(text)
    }
    onExited: function (exitCode, exitStatus) {
      // A row expanded while this fetch was in flight; catch it up.
      if (root.expandedDomain !== "" && root.details[root.key(root.expandedDomain)] === undefined)
        root.fetchDetail(root.expandedDomain)
    }
  }

  onExpandedDomainChanged: {
    if (expandedDomain !== "" && details[key(expandedDomain)] === undefined)
      fetchDetail(expandedDomain)
  }

  // ---- Snapshots -------------------------------------------------------
  // `--name` prints one per line so names with spaces survive. Never exits nonzero.
  property var snapshots: []
  property string snapshotScript: ""

  function fetchSnapshots(domain) {
    if (domain === "") return
    snapshotScript = "virsh -c " + shq(configuredUri) + " -q snapshot-list "
      + shq(domain) + " --name 2>/dev/null | sed '/^$/d;s/^/N /'"
    snapshotList.running = false
    snapshotList.running = true
  }

  function applySnapshots(text) {
    var found = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++)
      if (lines[i].charAt(0) === "N") found.push(lines[i].substring(2))
    snapshots = found
  }

  Process {
    id: snapshotList
    command: ["bash", "-lc", root.snapshotScript]
    stdout: StdioCollector {
      onStreamFinished: root.applySnapshots(text)
    }
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
    var command = "virsh -c " + shq(configuredUri) + " snapshot-create-as --domain " + shq(domain)
    // Empty, or sanitised away to nothing, gets libvirt's automatic name.
    if (clean !== "") command += " --name " + shq(clean)
    runScript(command + " >/dev/null", domain)
  }

  function revertSnapshot(domain, name) {
    if (confirmed("snapshot-revert", domain, name, configuredConfirmSnapshotRevert))
      runScript("virsh -c " + shq(configuredUri) + " snapshot-revert " + shq(domain)
        + " " + shq(name) + " >/dev/null", domain)
  }

  function deleteSnapshot(domain, name) {
    if (confirmed("snapshot-delete", domain, name, configuredConfirmSnapshotRevert))
      runScript("virsh -c " + shq(configuredUri) + " snapshot-delete " + shq(domain)
        + " " + shq(name) + " >/dev/null", domain)
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

  // The one place this widget writes user config. updateEntryInline replaces
  // the entry wholesale, so the existing keys have to be merged in or every
  // other setting on it is dropped.
  function persistSetting(name, value) {
    var entry = { id: moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    entry[name] = value

    // Applied locally first so the switch throws on the click itself; the
    // shell.json write comes back through the bar as the same value. That
    // assignment is also what re-fires the configured* bindings, so a setting
    // with a change handler — suppressCrashToasts has one — reconciles itself.
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") {
      settingsError = ""
      bar.shell.updateEntryInline(moduleName, entry)
    } else {
      // Degrades to session-only rather than failing silently.
      settingsError = "could not save: the shell did not expose updateEntryInline"
    }
  }

  // ---- Crash toast suppression ----------------------------------------
  // Four constraints, all load-bearing: flock (one widget per monitor, they race),
  // content compare (skips daemon-reload), marker line (only ever deletes our own
  // file), runtime dir not ~/.config (no uninstall hook, so it must not outlive us).
  property string crashToggleError: ""

  // Built at call time, never bound: a handler runs before siblings re-evaluate.
  property string crashToggleScript: ""

  function buildCrashToggleScript() {
    return [
    "set -u",
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
    "pattern=" + shq(configuredCrashIgnore),
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
    // Goes into a quoted systemd Environment= value.
    if (/["\n]/.test(configuredCrashIgnore)) {
      crashToggleError = "crashIgnore cannot contain quotes or newlines"
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
    command: ["bash", "-lc", root.crashToggleScript]
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

  // ---- Popup -----------------------------------------------------------
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // Wider in the settings view: Toggle elides its label and never wraps it,
    // and a setting worth a sentence does not fit the list view's width.
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

        Text {
          id: title
          anchors.left: backButton.visible ? backButton.right : parent.left
          anchors.leftMargin: backButton.visible ? Style.spacing.xs : 0
          anchors.right: headerActions.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: root.settingsOpen
            ? "Settings"
            : (root.snapshotDomain !== "" ? root.snapshotDomain : "Virtual machines")
          color: Color.popups.text
          font.family: popup.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        // A Row, not a chain of anchors: it skips invisible children, so the
        // buttons the settings view hides collapse instead of leaving a gap.
        Row {
          id: headerActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          PanelActionButton {
            id: settingsButton
            anchors.verticalCenter: parent.verticalCenter
            visible: root.listView
            iconText: "󰒓"
            tooltipText: "Settings"
            foreground: popup.foreground
            fontFamily: popup.fontFamily
            onClicked: root.openSettings()
          }

          PanelActionButton {
            id: refreshButton
            anchors.verticalCenter: parent.verticalCenter
            // Nothing to re-poll in the settings view.
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
          height: header.height + (row.expanded ? detailPane.height + Style.spacing.xs : 0)

          // Hover fill belongs to the header, not the whole delegate.
          Rectangle {
            id: header
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
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
          Column {
            id: detailPane
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.xs
            visible: row.expanded
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              visible: text !== ""
              elide: Text.ElideRight
              text: root.details[root.key(row.domainName)] || ""
              color: Qt.darker(Color.popups.text, 1.4)
              font.family: popup.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.spacing.xxs

              PanelActionButton {
                visible: row.isRunning
                iconText: "󰏤"
                tooltipText: "Pause"
                foreground: popup.foreground
                fontFamily: popup.fontFamily
                enabled: !root.busy
                onClicked: root.runAction("suspend", row.domainName)
              }

              PanelActionButton {
                visible: row.isRunning
                iconText: "󰜉"
                tooltipText: "Reboot"
                foreground: popup.foreground
                fontFamily: popup.fontFamily
                enabled: !root.busy
                onClicked: root.runAction("reboot", row.domainName)
              }

              PanelActionButton {
                visible: !row.isOff
                iconText: "󰆓"
                tooltipText: "Save state"
                foreground: popup.foreground
                fontFamily: popup.fontFamily
                enabled: !root.busy
                onClicked: root.runAction("managedsave", row.domainName)
              }

              PanelActionButton {
                visible: row.isSaved
                iconText: "󰆴"
                tooltipText: row.armedDiscard
                  ? "Click again to discard the saved state"
                  : "Discard saved state"
                foreground: row.armedDiscard ? popup.urgent : popup.foreground
                hoverColor: popup.urgent
                bordered: row.armedDiscard
                fontFamily: popup.fontFamily
                enabled: !root.busy
                onClicked: root.discardSaved(row.domainName)
              }

              PanelActionButton {
                visible: root.configuredShowSnapshots
                iconText: "󰄄"
                tooltipText: "Snapshots"
                foreground: popup.foreground
                fontFamily: popup.fontFamily
                enabled: !root.busy
                onClicked: root.openSnapshots(row.domainName)
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.domains.length === 0 && root.lastError === "" && root.listView
        wrapMode: Text.WordWrap
        text: "No domains defined on this connection."
        color: Color.popups.text
        opacity: 0.7
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Settings view ------------------------------------------------
      // One Toggle per setting; the row is stateless, so the click writes the
      // setting and the switch follows the configured* binding back.
      Column {
        id: settingsView
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
          radius: Style.cornerRadius
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
        wrapMode: Text.WordWrap
        // settingsError first: it is the only one the user just caused by hand,
        // so it must not sit behind a connection error it has nothing to do with.
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
        radius: Style.cornerRadius
        visible: root.configuredManager !== "" && root.listView
        color: managerMouse.containsMouse ? Style.hoverFill : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
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

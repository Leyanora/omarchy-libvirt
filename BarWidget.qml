import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Interface.js" as Interface
import "Virsh.js" as Virsh

// libvirt domains in the bar, driven entirely through `virsh`.
BarWidget {
  id: root
  moduleName: "leyanora.libvirt"

  // ---- View state ------------------------------------------------------
  // opened/open()/close() are how the shell routes summon/hide/toggle — keep the names.
  property bool popupOpen: false

  property string expandedDomain: ""
  property string snapshotDomain: ""
  property bool settingsOpen: false
  property string expandedColor: ""
  property string filterText: ""

  // One cursor, meaning an index into whichever list the open view shows. The
  // settings view has none: it is driven by Tab and the mouse.
  property int cursorIndex: -1

  readonly property bool opened: popupOpen

  readonly property var visibleDomains: Virsh.filterDomains(service.domains, root.filterText)

  readonly property string displayText: service.runningCount > 0 ? String(service.runningCount) : ""
  readonly property bool showLabel: !vertical && config.showCount && displayText !== ""
  readonly property string statsText: !vertical && config.barStats
    ? Interface.barStatsText(service.domains, service.stats, config.barDomains,
      config.barShowNames, config.barNameLength, config.barAliases, config.barMemory)
    : ""

  // Amber while something is suspended, urgent while the connection is down —
  // the glyph says which of the three it is before the popup is opened.
  readonly property color barTint: service.connectionDown
    ? (root.bar ? root.bar.urgent : Commons.Color.urgent)
    : (service.pausedCount > 0
      ? config.colorPaused
      : (root.bar ? root.bar.barForeground : Commons.Color.foreground))

  function open() {
    popupOpen = true
    service.refresh()
  }

  function close() {
    popupOpen = false
    service.clearArm()
    expandedDomain = ""
    snapshotDomain = ""
    settingsOpen = false
    expandedColor = ""
    filterText = ""
    cursorIndex = -1
  }

  function togglePanel() {
    if (popupOpen) close()
    else open()
  }

  // What broadcast(), the middle click and the wheel all land on.
  function refresh() {
    service.refresh()
  }

  function openSnapshots(domain) {
    service.clearArm()
    settingsOpen = false
    snapshotDomain = domain
    cursorIndex = -1
  }

  function openSettings() {
    service.clearArm()
    snapshotDomain = ""
    settingsOpen = true
    cursorIndex = -1
    // Entering settings always starts collapsed, however it was last left.
    expandedColor = ""
  }

  // Back leaves whichever sub-view is open; the two are mutually exclusive.
  function goBack() {
    cursorIndex = -1
    if (settingsOpen) {
      settingsOpen = false
      return
    }
    service.clearArm()
    snapshotDomain = ""
  }

  function openConsole(domain) {
    if (config.consoleCommand === "" || domain === "" || !bar) return
    service.launchConsole(config.consoleBinary,
      Virsh.expandTemplate(config.consoleCommand, config.uri, domain))
  }

  // ---- Keyboard --------------------------------------------------------
  // The cursor counts rows of the open view; the settings view offers none.
  function cursorCount() {
    if (settingsOpen) return 0
    if (snapshotDomain !== "") return service.snapshots.length
    return visibleDomains.length
  }

  function cursorDomain() {
    if (settingsOpen || snapshotDomain !== "") return null
    return cursorIndex >= 0 && cursorIndex < visibleDomains.length
      ? visibleDomains[cursorIndex]
      : null
  }

  function cursorSnapshot() {
    return snapshotDomain !== "" && cursorIndex >= 0 && cursorIndex < service.snapshots.length
      ? service.snapshots[cursorIndex]
      : ""
  }

  function moveCursor(delta) {
    var count = cursorCount()
    if (count === 0) {
      cursorIndex = -1
      return
    }
    var next = cursorIndex < 0 ? (delta > 0 ? 0 : count - 1) : cursorIndex + delta
    cursorIndex = Math.max(0, Math.min(count - 1, next))
  }

  function cursorToName(name) {
    for (var i = 0; i < visibleDomains.length; i++)
      if (visibleDomains[i].name === name) cursorIndex = i
  }

  // Enter runs the one verb the row's state makes obvious, and nothing destructive.
  function activateCursor() {
    var snapshot = cursorSnapshot()
    if (snapshot !== "") {
      service.revertSnapshot(snapshotDomain, snapshot)
      return
    }
    var domain = cursorDomain()
    if (domain === null) return
    if (domain.domainState === "running") service.runAction("shutdown", domain.name)
    else if (domain.domainState === "paused") service.runAction("resume", domain.name)
    else service.runAction("start", domain.name)
  }

  // `x`, on both lists, and armed on both.
  function deleteAtCursor() {
    var snapshot = cursorSnapshot()
    if (snapshot !== "") {
      service.deleteSnapshot(snapshotDomain, snapshot)
      return
    }
    var domain = cursorDomain()
    if (domain !== null && domain.domainState !== "shut off") service.forceOff(domain.name)
  }

  function expandCursor(delta) {
    var domain = cursorDomain()
    if (domain === null) return
    if (delta > 0) expandedDomain = domain.name
    else if (expandedDomain === domain.name) expandedDomain = ""
  }

  function keyAction(text) {
    if (text === "r" || text === "R") {
      refresh()
      return
    }
    if (text === "," ) {
      if (!settingsOpen) openSettings()
      return
    }
    var domain = cursorDomain()
    if (domain === null) return
    if ((text === "s" || text === "S") && config.showSnapshots) openSnapshots(domain.name)
    else if (text === "c" || text === "C") openConsole(domain.name)
  }

  // A shorter list must not leave the cursor pointing past its end.
  onVisibleDomainsChanged: if (cursorIndex >= visibleDomains.length) cursorIndex = -1

  // ---- Model -----------------------------------------------------------
  Settings {
    id: config
    entry: root.settings
    moduleName: root.moduleName
    shell: root.bar ? root.bar.shell : null
    onPersisted: function (next) { root.settings = next }
  }

  Service {
    id: service
    uri: config.uri
    interval: config.interval
    confirmForceOff: config.confirmForceOff
    confirmDiscardSaved: config.confirmDiscardSaved
    confirmSnapshotRevert: config.confirmSnapshotRevert
    statsEnabled: config.barStats || (root.popupOpen && config.showStats)
    statsInterval: config.statsInterval
    snapshotDomain: root.snapshotDomain
    detailDomain: root.expandedDomain
    // The settings view survives a failed poll on purpose; the row views cannot.
    onDomainsLost: {
      root.expandedDomain = ""
      root.snapshotDomain = ""
      root.cursorIndex = -1
    }
    onConsoleReady: function (command) {
      if (!root.bar) return
      root.bar.run(command)
      root.close()
    }
  }

  // ---- Bar button ------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Interface.barText(config.icon, root.displayText, root.showLabel, root.statsText)
    active: root.popupOpen
    useActiveColor: false
    foreground: root.barTint
    dimmed: service.runningCount === 0
    tooltipText: Interface.plain(Interface.barTooltip(service.lastError, service.domains,
      service.runningCount, config.uri, service.stats))
    fixedWidth: root.vertical ? root.barSize : -1
    fixedHeight: root.vertical ? root.barSize : -1

    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (config.onRightClick !== "" && root.bar)
          root.bar.run(config.onRightClick)
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
  Popup {
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen

    service: service
    config: config

    settingsOpen: root.settingsOpen
    snapshotDomain: root.snapshotDomain
    expandedDomain: root.expandedDomain
    expandedColor: root.expandedColor
    domains: root.visibleDomains
    cursorIndex: root.cursorIndex
    filterText: root.filterText

    onBackRequested: root.goBack()
    onSettingsRequested: root.openSettings()
    onSnapshotsRequested: function (name) { root.openSnapshots(name) }
    onConsoleRequested: function (name) { root.openConsole(name) }
    onExpandToggled: function (name) {
      root.expandedDomain = root.expandedDomain === name ? "" : name
    }
    onColorExpandToggled: function (name) {
      root.expandedColor = root.expandedColor === name ? "" : name
    }
    onManagerRequested: {
      if (root.bar) root.bar.run(config.manager)
      root.close()
    }
    onFilterChanged: function (text) {
      root.filterText = text
      root.cursorIndex = -1
    }
    onCursorRequested: function (index) { root.cursorIndex = index }
    onCursorNameRequested: function (name) { root.cursorToName(name) }

    onKeyMove: function (delta) { root.moveCursor(delta) }
    onKeyHorizontal: function (delta) { root.expandCursor(delta) }
    onKeyActivate: root.activateCursor()
    onKeyDelete: root.deleteAtCursor()
    onKeyText: function (text) { root.keyAction(text) }
    onEscapePressed: {
      if (root.settingsOpen || root.snapshotDomain !== "") root.goBack()
      else root.close()
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

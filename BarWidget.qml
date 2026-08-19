import QtQuick
import Quickshell.Io
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

  readonly property bool opened: popupOpen

  readonly property string displayText: service.runningCount > 0 ? String(service.runningCount) : ""
  readonly property bool showLabel: !vertical && config.showCount && displayText !== ""

  readonly property string summary: Interface.summaryText(service.lastError,
    service.totalCount, service.runningCount, config.uri)

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
  }

  function openSettings() {
    service.clearArm()
    snapshotDomain = ""
    settingsOpen = true
    // Entering settings always starts collapsed, however it was last left.
    expandedColor = ""
  }

  // Back leaves whichever sub-view is open; the two are mutually exclusive.
  function goBack() {
    if (settingsOpen) {
      settingsOpen = false
      return
    }
    service.clearArm()
    snapshotDomain = ""
  }

  function openConsole(domain) {
    if (config.consoleCommand === "" || domain === "" || !bar) return
    bar.run(Virsh.expandTemplate(config.consoleCommand, config.uri, domain))
    close()
  }

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
    snapshotDomain: root.snapshotDomain
    // The settings view survives a failed poll on purpose; the row views cannot.
    onDomainsLost: {
      root.expandedDomain = ""
      root.snapshotDomain = ""
    }
  }

  CrashWatch {
    id: crashWatch
    moduleName: root.moduleName
    suppress: config.suppressCrashToasts
    ignorePattern: config.crashIgnore
  }

  // ---- Bar button ------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Interface.barText(config.icon, root.displayText, root.showLabel)
    active: root.popupOpen
    useActiveColor: false
    dimmed: service.runningCount === 0
    tooltipText: Interface.plain(root.summary)
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
    crashWatch: crashWatch

    settingsOpen: root.settingsOpen
    snapshotDomain: root.snapshotDomain
    expandedDomain: root.expandedDomain
    expandedColor: root.expandedColor

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

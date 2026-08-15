import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// libvirt domains in the bar.
//
// The bar item is the glyph alone, dimmed when nothing is running; the count
// lives in its tooltip. The popup lists every domain on the connection with a
// green/amber/red state light and the actions that state allows — play a shut
// off or paused domain, stop a running one, force off either. Clicking a
// domain's name attaches a console to it.
//
// Everything goes through `virsh`, so the widget works against any libvirt URI
// the user can already reach from a shell. It never asks for credentials of
// its own: if `virsh -c <uri> list` fails in a terminal, it fails here too and
// the error is shown in the popup.
BarWidget {
  id: root
  moduleName: "leyanora.libvirt"

  // ---- Settings -------------------------------------------------------
  // Overridable per instance in shell.json:
  //   { "id": "leyanora.libvirt", "uri": "qemu:///system", "interval": 5 }
  readonly property string configuredUri: setting("uri", "qemu:///session")
  readonly property string configuredIcon: setting("icon", "󰒋")
  readonly property int configuredInterval: Math.max(2, setting("interval", 10))
  readonly property bool configuredShowCount: setting("showCount", false)
  readonly property bool configuredConfirmForceOff: setting("confirmForceOff", true)
  readonly property string configuredManager: setting("manager", "virt-manager -c " + shq(configuredUri))
  readonly property string configuredOnRightClick: setting("onRightClick", configuredManager)

  // Clicking a domain name opens its console. {uri} and {name} are replaced
  // with shell-quoted values, so any viewer works: remote-viewer, spicy, a
  // wrapper script of your own.
  readonly property string configuredConsole: setting("console", "virt-viewer --connect {uri} {name}")

  // The one place this widget departs from "never hardcode a color": a state
  // light has to read as green or red to mean anything, and a themed accent
  // does not. Overridable per instance all the same.
  readonly property color colorRunning: setting("colorRunning", "#3fb950")
  readonly property color colorPaused: setting("colorPaused", "#d29922")
  readonly property color colorStopped: setting("colorStopped", "#f85149")

  // ---- State ----------------------------------------------------------
  // domains is [{ name, domainState }], sorted running → paused → shut off.
  property var domains: []

  // Persistent networks that exist but are down. A domain wired to one cannot
  // start until its network does, so this counts as "the connection is not
  // fully up" alongside a hypervisor that will not answer at all.
  property var inactiveNetworks: []

  property string lastError: ""
  property string actionError: ""
  property bool busy: false

  // The domain whose force-off button has been clicked once and is waiting
  // for the confirming second click.
  property string armedDomain: ""

  readonly property int runningCount: countState("running")
  readonly property int totalCount: domains.length

  readonly property bool connectionDown: lastError !== ""

  readonly property string connectionLabel: connectionDown ? "Disconnected" : "Connected"
  readonly property bool needsBringUp: connectionDown || inactiveNetworks.length > 0

  readonly property string displayText: runningCount > 0 ? String(runningCount) : ""
  readonly property bool showLabel: !vertical && configuredShowCount && displayText !== ""

  readonly property string summary: lastError !== ""
    ? lastError
    : (totalCount === 0
      ? "No domains on " + configuredUri
      : runningCount + " of " + totalCount + " running")

  // ---- Popup lifecycle -------------------------------------------------
  // The bar routes `omarchy-shell shell summon/hide/toggle <id>` to whichever
  // widget exposes open/close/opened on its root, so keep these three names.
  property bool popupOpen: false

  readonly property bool opened: popupOpen

  function open() {
    popupOpen = true
    refresh()
  }

  function close() {
    popupOpen = false
    armedDomain = ""
  }

  function togglePanel() {
    if (popupOpen) close()
    else open()
  }

  // ---- Helpers ---------------------------------------------------------
  // Domain names are user-chosen strings that end up inside a shell command
  // and as JS object keys. Quote them for the shell, and prefix them as keys
  // so a domain called "constructor" cannot be mistaken for a live one.
  function shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function key(name) {
    return "d:" + name
  }

  function countState(state) {
    var found = 0
    for (var i = 0; i < domains.length; i++)
      if (domains[i].domainState === state) found++
    return found
  }

  function stateRank(state) {
    if (state === "running") return 0
    if (state === "paused") return 1
    return 2
  }

  function refresh() {
    poll.running = false
    poll.running = true
  }

  // ---- Polling ---------------------------------------------------------
  // Four fixed `virsh` calls regardless of how many domains exist, each line
  // tagged in column 0 so a name containing spaces still parses:
  //   R <name>  running   P <name>  paused
  //   A <name>  defined   N <name>  a persistent network that is down
  //   E <text>  the connection failed
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
    "virsh -c \"$u\" -q net-list --inactive --persistent --name 2>/dev/null | sed '/^$/d;s/^/N /'",
    "printf '%s\\n' \"$all\" | sed '/^$/d;s/^/A /'"
  ].join("\n")

  function applyPoll(text) {
    var running = ({})
    var paused = ({})
    var names = []
    var networks = []
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
        case "N": networks.push(value); break
        case "A": names.push(value); break
      }
    }

    lastError = error
    if (error !== "") {
      domains = []
      inactiveNetworks = []
      armedDomain = ""
      return
    }

    inactiveNetworks = networks

    var list = []
    for (var j = 0; j < names.length; j++) {
      var name = names[j]
      list.push({
        name: name,
        domainState: running[key(name)] ? "running" : (paused[key(name)] ? "paused" : "shut off")
      })
    }
    list.sort(function (a, b) {
      var byState = root.stateRank(a.domainState) - root.stateRank(b.domainState)
      return byState !== 0 ? byState : a.name.localeCompare(b.name)
    })

    domains = list

    // A domain that stopped on its own no longer has a force-off button to
    // confirm against, so drop the arming rather than leave it dangling.
    if (armedDomain !== "" && !running[key(armedDomain)] && !paused[key(armedDomain)])
      armedDomain = ""
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
  // One action at a time. `virsh shutdown` and friends return the moment the
  // request is queued, so the state we want to display lands a second or two
  // later — hence the settle timer rather than a single refresh.
  property string actionScript: ""

  function runScript(script) {
    if (busy || script === "") return
    actionError = ""
    armedDomain = ""
    actionScript = script
    busy = true
    action.running = true
  }

  function runAction(verb, domain) {
    if (domain === "") return
    runScript("virsh -c " + shq(configuredUri) + " " + verb + " " + shq(domain) + " >/dev/null")
  }

  // Bring the connection up: start whatever daemon the URI needs, wait for it
  // to answer, then start any persistent network that is down. A session URI
  // has no daemon to manage — virsh spawns `virtqemud --timeout=120` itself on
  // first contact — so there the work is the networks alone. A system URI is
  // behind systemd and polkit, and the prompt lands on Omarchy's polkit agent.
  //
  // `systemctl start` only, never `enable`: this is "make it work now", not a
  // change to what the machine does at boot.
  readonly property string bringUpScript: [
    "u=" + shq(configuredUri),
    "reachable() { virsh -c \"$u\" -q list --all --name >/dev/null 2>&1; }",
    "if ! reachable; then",
    "  case \"$u\" in",
    "    *session*) : ;;",
    "    *)",
    "      units=''",
    "      for s in virtqemud.socket virtnetworkd.socket virtstoraged.socket; do",
    "        systemctl cat \"$s\" >/dev/null 2>&1 && units=\"$units $s\"",
    "      done",
    "      if [ -z \"$units\" ] && systemctl cat libvirtd.socket >/dev/null 2>&1; then",
    "        units='libvirtd.socket'",
    "      fi",
    "      [ -n \"$units\" ] || { echo 'no libvirt systemd units on this host' >&2; exit 1; }",
    "      systemctl start $units || exit 1",
    "      ;;",
    "  esac",
    "fi",
    // Socket activation answers quickly, but not instantly.
    "for _ in 1 2 3 4 5 6 7 8 9 10; do",
    "  reachable && break",
    "  sleep 0.5",
    "done",
    "reachable || { echo \"still cannot reach $u\" >&2; exit 1; }",
    "virsh -c \"$u\" -q net-list --inactive --persistent --name 2>/dev/null | while IFS= read -r n; do",
    "  [ -n \"$n\" ] && virsh -c \"$u\" net-start \"$n\" >/dev/null 2>&1",
    "done",
    "exit 0"
  ].join("\n")

  function bringUp() {
    runScript(bringUpScript)
  }

  function openConsole(domain) {
    if (configuredConsole === "" || domain === "" || !bar) return
    var command = configuredConsole
      .replace(/\{uri\}/g, function () { return root.shq(root.configuredUri) })
      .replace(/\{name\}/g, function () { return root.shq(domain) })
    bar.run(command)
    close()
  }

  // Force off is `virsh destroy`: it cuts power to a live VM and loses
  // whatever the guest had not written out. Arm on the first click, act on
  // the second, and disarm on a timer so a stray click cannot linger.
  function forceOff(domain) {
    if (!configuredConfirmForceOff) {
      runAction("destroy", domain)
      return
    }
    if (armedDomain === domain) {
      disarm.stop()
      runAction("destroy", domain)
      return
    }
    armedDomain = domain
    disarm.restart()
  }

  Process {
    id: action
    command: ["bash", "-lc", root.actionScript]
    stderr: StdioCollector {
      // virsh prefixes the useful line with a generic "error:" banner; the
      // last line is the one worth showing.
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        root.actionError = lines[lines.length - 1]
      }
    }
    onExited: function (exitCode, exitStatus) {
      root.busy = false
      if (exitCode === 0) root.actionError = ""
      settle.ticks = 0
      settle.restart()
      root.refresh()
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
    onTriggered: root.armedDomain = ""
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
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property color foreground: root.bar ? root.bar.foreground : Color.popups.text
    readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.spacing.sm

      // Title and a manual refresh, since the poll interval can be long.
      Item {
        width: parent.width
        implicitHeight: Math.max(title.implicitHeight, refreshButton.implicitHeight)

        Text {
          id: title
          anchors.left: parent.left
          anchors.right: connectButton.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: "Virtual machines"
          color: Color.popups.text
          font.family: popup.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        // Only offered when there is something to bring up: a hypervisor that
        // will not answer, or a network that is down.
        PanelActionButton {
          id: connectButton
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.spacing.xxs
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.needsBringUp ? "󰚦" : "󰚥"
          tooltipText: root.connectionDown
            ? "Start libvirt for this connection"
            : (root.inactiveNetworks.length > 0
              ? "Start " + root.inactiveNetworks.length + " inactive network(s)"
              : "Connection is up")
          foreground: root.needsBringUp ? Color.accent : popup.foreground
          hoverColor: Color.accent
          bordered: root.needsBringUp
          fontFamily: popup.fontFamily
          enabled: !root.busy && root.needsBringUp
          onClicked: root.bringUp()
        }

        PanelActionButton {
          id: refreshButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑓"
          tooltipText: "Refresh"
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          enabled: !root.busy
          onClicked: root.refresh()
        }
      }

      // Whether libvirt answered, not which connection it is. The URI is still
      // worth having when two instances are in the bar, so it lives on hover.
      Text {
        id: connectionText
        width: parent.width
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

      PanelSeparator {
        foreground: popup.foreground
      }

      // The domain list. Capped so a host with thirty VMs scrolls instead of
      // growing a popup taller than the screen.
      ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, Style.space(300))
        visible: root.domains.length > 0
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: root.domains

        delegate: Rectangle {
          id: row
          required property var modelData

          readonly property string domainName: row.modelData.name
          readonly property string domainState: row.modelData.domainState
          readonly property bool isRunning: row.domainState === "running"
          readonly property bool isPaused: row.domainState === "paused"
          readonly property bool isOff: !isRunning && !isPaused
          readonly property bool armed: root.armedDomain === row.domainName

          width: list.width
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
            color: row.isRunning ? root.colorRunning : (row.isPaused ? root.colorPaused : root.colorStopped)
          }

          // The name is the console handle: click it to attach a viewer. Only
          // a domain that is up has a console to attach to.
          Text {
            id: nameText
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
              iconText: "󰐊"
              tooltipText: "Start"
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

            // A guest with no ACPI handler — anything mid-install, anything
            // hung — ignores `virsh shutdown` entirely, so stopping it at all
            // needs the hard path. Two clicks, because it discards guest state.
            PanelActionButton {
              visible: !row.isOff
              iconText: "󱐋"
              tooltipText: row.armed ? "Click again to force off" : "Force off"
              foreground: row.armed ? popup.urgent : popup.foreground
              hoverColor: popup.urgent
              bordered: row.armed
              fontFamily: popup.fontFamily
              enabled: !root.busy
              onClicked: root.forceOff(row.domainName)
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.domains.length === 0 && root.lastError === ""
        wrapMode: Text.WordWrap
        text: "No domains defined on this connection."
        color: Color.popups.text
        opacity: 0.7
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: root.lastError !== "" ? root.lastError : root.actionError
        color: popup.urgent
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      PanelSeparator {
        visible: root.configuredManager !== ""
        foreground: popup.foreground
      }

      Rectangle {
        width: parent.width
        height: Style.space(28)
        radius: Style.cornerRadius
        visible: root.configuredManager !== ""
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
  // Reachable from scripts and keybindings:
  //   omarchy-shell leyanora.libvirt toggle
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

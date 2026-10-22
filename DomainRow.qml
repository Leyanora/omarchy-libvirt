import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Interface.js" as Interface
import "Virsh.js" as Virsh

// One domain: state light, name, power buttons, and the chip grid it expands into.
Item {
  id: row

  required property var modelData

  property var service: null

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color urgent: Commons.Color.urgent
  property int radius: Style.cornerRadius
  property color colorRunning: Commons.Color.foreground
  property color colorPaused: Commons.Color.foreground
  property color colorStopped: Commons.Color.foreground

  property bool expanded: false
  property bool showSnapshots: true
  property bool consoleEnabled: true
  property bool showStats: true

  // This domain's latest sample, or undefined while nothing is sampling it.
  property var usage: undefined

  // Keyboard and mouse share one highlight, so the row never paints from hover.
  property bool hasCursor: false

  signal consoleRequested(string name)
  signal snapshotsRequested(string name)
  signal expandToggled(string name)
  signal cursorRequested(string name)

  readonly property string domainName: row.modelData.name
  readonly property string domainState: row.modelData.domainState
  readonly property bool isRunning: row.domainState === "running"
  readonly property bool isPaused: row.domainState === "paused"
  readonly property bool isOff: !isRunning && !isPaused
  readonly property bool isSaved: row.modelData.saved === true && row.isOff
  readonly property bool armedForceOff: row.service.isArmed("destroy", row.domainName, "")
  readonly property bool armedDiscard: row.service.isArmed("managedsave-remove", row.domainName, "")
  readonly property bool working: row.service.busy && row.service.busyDomain === row.domainName
  readonly property bool canConsole: !row.isOff && row.consoleEnabled

  // The clock is passed in so this binding depends on it and re-counts each second.
  readonly property int shutdownWaited: row.isRunning
    ? row.service.waitedFor(row.domainName, row.service.clock)
    : 0
  readonly property bool stalled: row.shutdownWaited >= Interface.STALL_AFTER
  readonly property bool showUsage: row.isRunning && row.showStats && row.usage !== undefined

  width: ListView.view.width
  height: frame.height

  // The border is what makes an expanded row read as one object.
  BorderSurface {
    id: frame
    width: parent.width
    // The pane's own top margin is in the sum too, or the bottom edge clips.
    height: header.height + (row.expanded
      ? detailPane.height + Style.spacing.xs + Style.spacing.sm + frame.borderTop * 2
      : 0)
    radius: row.radius
    // Filled like Toggle at rest, so the name row and the chips read as one card.
    color: row.expanded ? Style.normalFillFor(row.foreground, Commons.Color.accent) : "transparent"
    borderSpec: row.expanded
      ? Border.flat(Qt.darker(row.foreground, 1.8), Math.max(1, Style.space(1)))
      : Border.none()

    // The card grows into its chips rather than snapping open under the cursor.
    Behavior on height {
      NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    // Cursor fill belongs to the header, not the whole delegate.
    Rectangle {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: frame.borderTop
      height: Style.space(30)
      radius: row.radius
      color: row.hasCursor ? Style.hoverFill : "transparent"

      Behavior on color { ColorAnimation { duration: 60 } }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: if (containsMouse) row.cursorRequested(row.domainName)
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
          : (row.isRunning ? row.colorRunning : (row.isPaused ? row.colorPaused : row.colorStopped))
        border.width: row.isSaved ? Math.max(1, Style.space(2)) : 0
        border.color: row.colorStopped
        visible: !row.working
      }

      Text {
        anchors.centerIn: dot
        visible: row.working
        textFormat: Text.PlainText
        text: Interface.Glyph.working
        color: Commons.Color.accent
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: nameText
        anchors.left: dot.right
        anchors.leftMargin: Style.spacing.md
        anchors.right: usage.visible ? usage.left : actions.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: row.domainName
        color: nameMouse.containsMouse && row.canConsole ? Commons.Color.accent : Commons.Color.popups.text
        opacity: row.isOff ? 0.6 : 1.0
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.underline: nameMouse.containsMouse && row.canConsole

        // Hover is live even on a shut off row: an elided name is worth reading back.
        MouseArea {
          id: nameMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.canConsole ? Qt.PointingHandCursor : Qt.ArrowCursor
          acceptedButtons: row.canConsole ? Qt.LeftButton : Qt.NoButton
          onClicked: row.consoleRequested(row.domainName)

          PanelToolTip {
            visible: nameMouse.containsMouse && text !== ""
            text: Interface.nameTooltip(row.domainName, nameText.truncated, row.canConsole)
            fontFamily: row.fontFamily
          }
        }
      }

      Row {
        id: usage
        anchors.right: actions.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md
        visible: row.showUsage
        opacity: row.showUsage ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Hot in the theme's urgent, not a fourth hardcoded colour.
        UsageFigure {
          glyph: Interface.Glyph.cpu
          value: Interface.cpuText(row.usage)
          widest: "100%"
          fraction: row.usage ? row.usage.cpu / 100 : -1
          tint: row.usage && row.usage.cpu >= Interface.CPU_HOT ? row.urgent : Commons.Color.accent
          foreground: row.foreground
          fontFamily: row.fontFamily
        }

        UsageFigure {
          glyph: Interface.Glyph.memory
          value: row.usage ? Virsh.formatKiBShort(row.usage.memUsed) : ""
          widest: "99.9G"
          fraction: row.usage && row.usage.memTotal > 0 ? row.usage.memUsed / row.usage.memTotal : -1
          foreground: row.foreground
          fontFamily: row.fontFamily
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
          iconText: row.isSaved ? Interface.Glyph.restore : Interface.Glyph.start
          tooltipText: row.isSaved ? "Restore" : "Start"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("start", row.domainName)
        }

        PanelActionButton {
          visible: row.isPaused
          iconText: Interface.Glyph.start
          tooltipText: "Resume"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("resume", row.domainName)
        }

        PanelActionButton {
          visible: row.isRunning
          iconText: Interface.Glyph.shutdown
          tooltipText: "Shut down"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("shutdown", row.domainName)
        }

        // Bordered while a shutdown goes unanswered: the escalation the user wants next.
        PanelActionButton {
          visible: !row.isOff
          iconText: Interface.Glyph.forceOff
          tooltipText: row.armedForceOff
            ? "Click again to force off"
            : (row.stalled ? Interface.stalledTooltip(row.shutdownWaited) : "Force off")
          foreground: row.armedForceOff || row.stalled ? row.urgent : row.foreground
          hoverColor: row.urgent
          bordered: row.armedForceOff || row.stalled
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.forceOff(row.domainName)

          ArmProgress {
            fraction: row.armedForceOff ? row.service.armFraction : 0
            tint: row.urgent
          }
        }

        PanelActionButton {
          iconText: row.expanded ? Interface.Glyph.collapse : Interface.Glyph.expand
          tooltipText: row.expanded ? "Less" : "More"
          foreground: row.foreground
          fontFamily: row.fontFamily
          onClicked: row.expandToggled(row.domainName)
        }
      }
    }

    // ---- Expanded detail ----------------------------------------
    // Frame carries the fill; this is the layout box, inset to the state dot's column.
    Item {
      id: detailPane
      anchors.top: header.bottom
      anchors.topMargin: Style.spacing.xs
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: frame.borderLeft
      anchors.rightMargin: frame.borderRight
      visible: row.expanded
      height: chips.implicitHeight + detailLine.height + Style.spacing.sm * 2

      // Empty until both probes answer, and it keeps its row so the chips do not jump.
      Text {
        id: detailLine
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.sm
        anchors.rightMargin: Style.spacing.sm
        height: implicitHeight
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: row.expanded ? Interface.detailLine(row.service.detail, row.service.detailReason,
          row.showUsage ? row.usage : undefined) : ""
        color: Qt.darker(Commons.Color.popups.text, 1.4)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Positioners skip invisible children, so this reflows for 1..4 chips.
      Row {
        id: chips
        anchors.top: detailLine.bottom
        anchors.topMargin: Style.spacing.sm
        anchors.horizontalCenter: parent.horizontalCenter

        // Counted off the positioner, never off the state: a new chip needs nothing here.
        readonly property int shown: {
          var n = 0
          for (var i = 0; i < chips.children.length; i++)
            if (chips.children[i].visible) n++
          return n
        }

        // A full set gets room to breathe; one or two read better kept together.
        spacing: chips.shown > 3 ? Style.spacing.xxl : Style.spacing.xs

        ActionChip {
          visible: row.isRunning
          iconText: Interface.Glyph.pause
          tooltipText: "Pause"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("suspend", row.domainName)
        }

        ActionChip {
          visible: row.isRunning
          iconText: Interface.Glyph.reboot
          tooltipText: "Reboot"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("reboot", row.domainName)
        }

        ActionChip {
          visible: !row.isOff
          iconText: Interface.Glyph.save
          tooltipText: "Save state"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("managedsave", row.domainName)
        }

        // Only the accent shows the arm now, so the tooltip names what the second click does.
        ActionChip {
          visible: row.isSaved
          iconText: Interface.Glyph.discard
          tooltipText: row.armedDiscard ? "Click again to discard" : "Discard"
          foreground: row.foreground
          hoverColor: row.urgent
          accented: row.armedDiscard
          armFraction: row.service.armFraction
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.discardSaved(row.domainName)
        }

        ActionChip {
          visible: row.showSnapshots
          iconText: Interface.Glyph.snapshots
          tooltipText: "Snapshots"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.snapshotsRequested(row.domainName)
        }
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface

// One domain: state light, name, power buttons, and the chip grid it expands into.
Item {
  id: row

  required property var modelData

  property var service: null

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color urgent: Color.urgent
  property int radius: Style.cornerRadius
  property color colorRunning: Color.foreground
  property color colorPaused: Color.foreground
  property color colorStopped: Color.foreground

  property bool expanded: false
  property bool showSnapshots: true
  property bool consoleEnabled: true

  signal consoleRequested(string name)
  signal snapshotsRequested(string name)
  signal expandToggled(string name)

  readonly property string domainName: row.modelData.name
  readonly property string domainState: row.modelData.domainState
  readonly property bool isRunning: row.domainState === "running"
  readonly property bool isPaused: row.domainState === "paused"
  readonly property bool isOff: !isRunning && !isPaused
  readonly property bool isSaved: row.modelData.saved === true && row.isOff
  readonly property bool armedForceOff: row.service.isArmed("destroy", row.domainName, "")
  readonly property bool armedDiscard: row.service.isArmed("managedsave-remove", row.domainName, "")
  readonly property bool working: row.service.busy && row.service.busyDomain === row.domainName

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
    color: row.expanded ? Style.normalFillFor(row.foreground, Color.accent) : "transparent"
    borderSpec: row.expanded
      ? Border.flat(Qt.darker(row.foreground, 1.8), Math.max(1, Style.space(1)))
      : Border.none()

    // Hover fill belongs to the header, not the whole delegate.
    Rectangle {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: frame.borderTop
      height: Style.space(30)
      radius: row.radius
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
        color: Color.accent
        font.family: row.fontFamily
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
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.underline: nameMouse.containsMouse

        MouseArea {
          id: nameMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !row.isOff && row.consoleEnabled
          cursorShape: Qt.PointingHandCursor
          onClicked: row.consoleRequested(row.domainName)

          PanelToolTip {
            visible: nameMouse.containsMouse
            text: "Open console"
            fontFamily: row.fontFamily
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

        PanelActionButton {
          visible: !row.isOff
          iconText: Interface.Glyph.forceOff
          tooltipText: row.armedForceOff ? "Click again to force off" : "Force off"
          foreground: row.armedForceOff ? row.urgent : row.foreground
          hoverColor: row.urgent
          bordered: row.armedForceOff
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.forceOff(row.domainName)
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
    // Frame carries the fill; this is the layout box, inset to the dot's column.
    Item {
      id: detailPane
      anchors.top: header.bottom
      anchors.topMargin: Style.spacing.xs
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: frame.borderLeft
      anchors.rightMargin: frame.borderRight
      visible: row.expanded
      height: chipGrid.implicitHeight + Style.spacing.sm * 2

      // Positioners skip invisible children, so this reflows for 1..4 chips.
      Grid {
        id: chipGrid
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.sm
        columns: 2
        spacing: Style.spacing.xs

        readonly property real chipWidth: (width - spacing) / 2

        ActionChip {
          visible: row.isRunning
          width: chipGrid.chipWidth
          iconText: Interface.Glyph.pause
          label: "Pause"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("suspend", row.domainName)
        }

        ActionChip {
          visible: row.isRunning
          width: chipGrid.chipWidth
          iconText: Interface.Glyph.reboot
          label: "Reboot"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("reboot", row.domainName)
        }

        ActionChip {
          visible: !row.isOff
          width: chipGrid.chipWidth
          iconText: Interface.Glyph.save
          label: "Save state"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.runAction("managedsave", row.domainName)
        }

        // The label carries the arm state, so no tooltip has to hold a second string.
        ActionChip {
          visible: row.isSaved
          width: chipGrid.chipWidth
          iconText: Interface.Glyph.discard
          label: row.armedDiscard ? "Click again" : "Discard"
          foreground: row.foreground
          hoverColor: row.urgent
          accented: row.armedDiscard
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.service.discardSaved(row.domainName)
        }

        ActionChip {
          visible: row.showSnapshots
          width: chipGrid.chipWidth
          iconText: Interface.Glyph.snapshots
          label: "Snapshots"
          foreground: row.foreground
          fontFamily: row.fontFamily
          enabled: !row.service.busy
          onClicked: row.snapshotsRequested(row.domainName)
        }
      }
    }
  }
}

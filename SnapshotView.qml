import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface

// The snapshot view: one row per snapshot, and the fields that take a new one.
Column {
  id: snapshotView

  property var service: null
  property string domain: ""

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color urgent: Color.urgent
  property int radius: Style.cornerRadius

  property int cursorIndex: -1

  signal cursorRequested(int index)
  // Focus is handed back explicitly: dropping it would leave no item holding keys.
  signal keysReleased()

  function create() {
    snapshotView.service.createSnapshot(snapshotView.domain, snapshotName.text, snapshotNote.text)
    snapshotName.text = ""
    snapshotNote.text = ""
    snapshotView.keysReleased()
  }

  width: parent.width
  spacing: Style.spacing.sm

  // Escape propagates up from whichever field holds the keys, and hands them back.
  Keys.onEscapePressed: snapshotView.keysReleased()

  ListView {
    width: parent.width
    height: Math.min(contentHeight, Style.space(220))
    visible: snapshotView.service.snapshots.length > 0
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    model: snapshotView.service.snapshots

    delegate: Rectangle {
      id: snapshotRow
      required property var modelData
      required property int index

      readonly property string snapshotName: String(snapshotRow.modelData)
      readonly property bool isCurrent: snapshotRow.snapshotName === snapshotView.service.currentSnapshot
      readonly property bool hasCursor: snapshotView.cursorIndex === snapshotRow.index
      readonly property bool armedRevert: snapshotView.service.isArmed("snapshot-revert", snapshotView.domain, snapshotRow.snapshotName)
      readonly property bool armedDelete: snapshotView.service.isArmed("snapshot-delete", snapshotView.domain, snapshotRow.snapshotName)

      width: ListView.view.width
      height: Style.space(30)
      radius: snapshotView.radius
      color: snapshotRow.hasCursor ? Style.hoverFill : "transparent"

      Behavior on color { ColorAnimation { duration: 60 } }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: if (containsMouse) snapshotView.cursorRequested(snapshotRow.index)
      }

      // Which snapshot a revert would land on is the first thing a list of names hides.
      Text {
        id: currentMark
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        visible: snapshotRow.isCurrent
        textFormat: Text.PlainText
        text: Interface.Glyph.current
        color: Color.accent
        font.family: snapshotView.fontFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: currentMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton

          PanelToolTip {
            visible: currentMouse.containsMouse
            text: "Current snapshot"
            fontFamily: snapshotView.fontFamily
          }
        }
      }

      Text {
        anchors.left: parent.left
        // The mark's column is reserved on every row, or the names would not line up.
        anchors.leftMargin: Style.spacing.sm + currentMark.width + Style.spacing.xs
        anchors.right: snapshotActions.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: snapshotRow.snapshotName
        color: Color.popups.text
        font.family: snapshotView.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        id: snapshotActions
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        PanelActionButton {
          iconText: Interface.Glyph.revert
          tooltipText: snapshotRow.armedRevert ? "Click again to revert" : "Revert to this snapshot"
          foreground: snapshotRow.armedRevert ? snapshotView.urgent : snapshotView.foreground
          hoverColor: snapshotView.urgent
          bordered: snapshotRow.armedRevert
          fontFamily: snapshotView.fontFamily
          enabled: !snapshotView.service.busy
          onClicked: snapshotView.service.revertSnapshot(snapshotView.domain, snapshotRow.snapshotName)

          ArmProgress {
            fraction: snapshotRow.armedRevert ? snapshotView.service.armFraction : 0
            tint: snapshotView.urgent
          }
        }

        PanelActionButton {
          iconText: Interface.Glyph.discard
          tooltipText: snapshotRow.armedDelete ? "Click again to delete" : "Delete snapshot"
          foreground: snapshotRow.armedDelete ? snapshotView.urgent : snapshotView.foreground
          hoverColor: snapshotView.urgent
          bordered: snapshotRow.armedDelete
          fontFamily: snapshotView.fontFamily
          enabled: !snapshotView.service.busy
          onClicked: snapshotView.service.deleteSnapshot(snapshotView.domain, snapshotRow.snapshotName)

          ArmProgress {
            fraction: snapshotRow.armedDelete ? snapshotView.service.armFraction : 0
            tint: snapshotView.urgent
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    visible: snapshotView.service.snapshots.length === 0
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: "No snapshots for this domain."
    color: Color.popups.text
    opacity: 0.7
    font.family: snapshotView.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // Free text libvirt stores verbatim, so it gets its own row rather than a cleaned one.
  TextField {
    id: snapshotNote
    width: parent.width
    placeholderText: "Description (optional)"
    enabled: !snapshotView.service.busy
    foreground: snapshotView.foreground
    font.family: snapshotView.fontFamily
    onAccepted: snapshotView.create()
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(snapshotName.implicitHeight, createButton.implicitHeight)

    TextField {
      id: snapshotName
      anchors.left: parent.left
      anchors.right: createButton.left
      anchors.rightMargin: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "New snapshot name"
      enabled: !snapshotView.service.busy
      foreground: snapshotView.foreground
      font.family: snapshotView.fontFamily
      onAccepted: snapshotView.create()
    }

    PanelActionButton {
      id: createButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: Interface.Glyph.create
      tooltipText: "Take snapshot"
      foreground: snapshotView.foreground
      fontFamily: snapshotView.fontFamily
      enabled: !snapshotView.service.busy
      onClicked: snapshotView.create()
    }
  }
}

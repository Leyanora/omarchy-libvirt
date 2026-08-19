import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface

// The snapshot view: one row per snapshot, and the field that takes a new one.
Column {
  id: snapshotView

  property var service: null
  property string domain: ""

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color urgent: Color.urgent
  property int radius: Style.cornerRadius

  width: parent.width
  spacing: Style.spacing.sm

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

      readonly property string snapshotName: String(snapshotRow.modelData)
      readonly property bool armedRevert: snapshotView.service.isArmed("snapshot-revert", snapshotView.domain, snapshotRow.snapshotName)
      readonly property bool armedDelete: snapshotView.service.isArmed("snapshot-delete", snapshotView.domain, snapshotRow.snapshotName)

      width: ListView.view.width
      height: Style.space(30)
      radius: snapshotView.radius
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
      onAccepted: {
        snapshotView.service.createSnapshot(snapshotView.domain, text)
        text = ""
      }
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
      onClicked: {
        snapshotView.service.createSnapshot(snapshotView.domain, snapshotName.text)
        snapshotName.text = ""
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui

// Icon plus label: PanelActionButton is icon-only and the host Ui tree is read-only.
BorderSurface {
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

  // Centred as a pair: the chips are a grid, so a shared centre line reads calmer.
  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    // Elide against what the chip actually offers; the row itself hugs its content.
    readonly property real labelRoom: chip.width - chip.borderLeft - chip.borderRight
      - Style.spacing.md * 2 - chipIcon.width - chipRow.spacing

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
      width: Math.min(implicitWidth, chipRow.labelRoom)
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

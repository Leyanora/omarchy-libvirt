import QtQuick
import qs.Commons
import qs.Ui

// A raised icon pill: PanelActionButton is flat at rest, and Ui/ is read-only.
BorderSurface {
  id: chip

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Color.foreground
  property color hoverColor: foreground
  property string fontFamily: Style.font.family
  // Armed half of arm-then-confirm: the chip wears the urgent colour and a border.
  property bool accented: false

  signal clicked()

  implicitHeight: Math.max(Style.space(26), Style.font.icon + Style.spacing.md * 2)
  // Hugs its glyph, so a Row of them reflows without anyone counting the visible ones.
  implicitWidth: Math.max(chip.implicitHeight,
    chipIcon.implicitWidth + Style.spacing.md * 4 + chip.borderLeft + chip.borderRight)
  radius: height / 2

  readonly property bool hot: chipMouse.containsMouse && chip.enabled
  readonly property color tint: accented ? hoverColor : foreground

  color: hot ? Style.hoverFillFor(hoverColor, hoverColor) : Style.normalFillFor(foreground, Color.accent)
  borderSpec: Border.controlSpec(hot || accented ? "hover-cursor" : "normal", tint, Color.accent)

  Behavior on color { ColorAnimation { duration: 60 } }

  Text {
    id: chipIcon
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: chip.iconText
    color: chip.enabled ? chip.tint : Qt.darker(chip.foreground, 2.0)
    font.family: chip.fontFamily
    font.pixelSize: Style.font.icon
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: chip.enabled
    cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: chip.clicked()
  }

  PanelToolTip {
    visible: chip.tooltipText !== "" && chipMouse.containsMouse
    text: chip.tooltipText
    fontFamily: chip.fontFamily
  }
}

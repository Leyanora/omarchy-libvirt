import QtQuick
import qs.Commons
import qs.Ui

// A titled box of related settings — three bare rows in a column would not read
// as three parts of one thing.
BorderSurface {
  id: group

  property string title: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  default property alias content: rows.children

  height: rows.implicitHeight + Style.spacing.sm * 2
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.flat(Qt.darker(group.foreground, 1.8), Math.max(1, Style.space(1)))

  Column {
    id: rows
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.sm
    spacing: Style.spacing.xs

    PanelSectionHeader {
      text: group.title
      foreground: group.foreground
      fontFamily: group.fontFamily
    }
  }
}

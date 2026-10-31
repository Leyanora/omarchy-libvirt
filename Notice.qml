import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A missing tool or a refusal, boxed and centred so it reads as a state, not a stray line.
BorderSurface {
  id: notice

  // { glyph, title, body, command } from Interface.notice(), or null for nothing to say.
  property var model: null
  property color foreground: Commons.Color.popups.text
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family

  visible: model !== null
  height: visible ? lines.implicitHeight + Style.spacing.lg * 2 : 0
  radius: Style.cornerRadius
  color: Qt.rgba(notice.urgent.r, notice.urgent.g, notice.urgent.b, 0.08)
  borderSpec: Border.flat(notice.urgent, Math.max(1, Style.space(1)))

  Column {
    id: lines
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: Style.spacing.lg
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: notice.model ? notice.model.glyph : ""
      color: notice.urgent
      font.family: notice.fontFamily
      font.pixelSize: Style.font.heading * 2
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: notice.model ? notice.model.title : ""
      color: notice.urgent
      font.family: notice.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: notice.model ? notice.model.body : ""
      color: Qt.darker(notice.foreground, 1.2)
      font.family: notice.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Shown, never run: the widget makes no package call of its own.
    BorderSurface {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: notice.model !== null && notice.model.command !== ""
      width: Math.min(parent.width, command.implicitWidth + Style.spacing.lg * 2)
      height: command.implicitHeight + Style.spacing.sm * 2
      radius: notice.radius
      color: Style.normalFillFor(notice.foreground, Commons.Color.accent)
      borderSpec: Border.flat(Qt.darker(notice.foreground, 1.8), Math.max(1, Style.space(1)))

      Text {
        id: command
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - Style.spacing.lg * 2)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: notice.model ? notice.model.command : ""
        color: notice.foreground
        font.family: notice.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}

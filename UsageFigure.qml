import QtQuick
import qs.Commons
import qs.Commons as Commons

// One usage figure on a row: a glyph, its value, and a hairline gauge under both.
Item {
  id: figure

  property string glyph: ""
  property string value: ""
  // Sizes the figure, so the name beside it does not shuffle as the digits change.
  property string widest: ""
  // 0..1; anything else leaves the track empty rather than guessing.
  property real fraction: -1
  property color tint: Commons.Color.accent
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  implicitWidth: Math.ceil(metrics.advanceWidth)
  implicitHeight: label.implicitHeight + Style.space(2) + gauge.height

  TextMetrics {
    id: metrics
    font: label.font
    text: figure.glyph + " " + figure.widest
  }

  Text {
    id: label
    anchors.top: parent.top
    anchors.right: parent.right
    textFormat: Text.PlainText
    text: figure.glyph + " " + figure.value
    color: Qt.darker(Commons.Color.popups.text, 1.4)
    font.family: figure.fontFamily
    font.pixelSize: Style.font.caption
    font.features: { "tnum": 1 }
  }

  Rectangle {
    id: gauge
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: Style.hoverFillFor(figure.foreground, Commons.Color.accent)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      radius: parent.radius
      width: parent.width * (figure.fraction >= 0 ? Math.min(1, figure.fraction) : 0)
      color: figure.tint

      // Eased, so a sample landing every few seconds reads as movement, not a jump.
      Behavior on width {
        NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
      }
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }
}

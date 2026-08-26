import QtQuick
import qs.Commons

// The disarm window, drawn. Arm-then-confirm is otherwise invisible: nothing on
// screen says how long the second click still has.
Rectangle {
  id: bar

  // 1 at the moment of arming, 0 when the window has run out.
  property real fraction: 0
  property color tint: Color.urgent

  anchors.bottom: parent.bottom
  anchors.horizontalCenter: parent.horizontalCenter
  width: Math.max(0, parent.width - Style.spacing.sm * 2) * Math.max(0, Math.min(1, bar.fraction))
  height: Math.max(1, Style.space(2))
  radius: height / 2
  color: bar.tint
  visible: bar.fraction > 0
}

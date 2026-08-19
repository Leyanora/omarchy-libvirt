import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface
import "Settings.js" as Config

// A saturation/value square over a hue strip, with the value as hex and R/G/B.
Item {
  id: picker

  property var config: null
  property string colorName: ""

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int radius: Style.cornerRadius

  // Authoritative and seeded only on open: a grey reports no hue to derive one from.
  property real hue: 0
  property real sat: 0
  property real val: 0

  readonly property color current: Qt.hsva(picker.hue, picker.sat, picker.val, 1)
  readonly property string currentHex: Config.hexOf(current.r, current.g, current.b)

  implicitHeight: layout.implicitHeight

  function setFrom(value) {
    var c = typeof value === "string" ? Qt.color(value) : value
    if (c.hsvSaturation > 0 && c.hsvHue >= 0) picker.hue = c.hsvHue
    picker.sat = c.hsvSaturation
    picker.val = c.hsvValue
  }

  // One write per gesture — bound to a drag this would rewrite shell.json per pixel.
  function commit() {
    picker.config.persistColor(picker.colorName, picker.currentHex)
  }

  // Presets and reset persist their literal hex, so no hsv round-trip can shift it.
  function applyHex(value) {
    if (!picker.config.persistColor(picker.colorName, value)) return false
    setFrom(value)
    return true
  }

  // Qt treats hue 1.0 as out of range, so the strip stops just short of wrapping.
  function setHue(fraction) {
    picker.hue = Math.min(0.9999, Config.clamp01(fraction))
  }

  function setChannels() {
    picker.setFrom(Qt.rgba(Config.clamp01(Number(red.field.text) / 255),
      Config.clamp01(Number(green.field.text) / 255),
      Config.clamp01(Number(blue.field.text) / 255), 1))
    picker.commit()
  }


  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.spacing.xs

    // Pure hue underneath, white across, black down — the standard two-gradient build.
    Rectangle {
      id: svArea
      width: parent.width
      height: Style.space(110)
      radius: picker.radius
      color: Qt.hsva(picker.hue, 1, 1, 1)

      // QML colour literals are #aarrggbb, so the transparent stops lead with 00.
      Rectangle {
        anchors.fill: parent
        radius: svArea.radius
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#ffffffff" }
          GradientStop { position: 1.0; color: "#00ffffff" }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: svArea.radius
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "#00000000" }
          GradientStop { position: 1.0; color: "#ff000000" }
        }
      }

      Rectangle {
        x: picker.sat * svArea.width - width / 2
        y: (1 - picker.val) * svArea.height - height / 2
        width: Style.space(12)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Style.space(2))
        // Flips against the patch underneath, so the ring never disappears.
        border.color: picker.val > 0.55 && picker.sat < 0.65 ? "#000000" : "#ffffff"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onPressed: function (mouse) { svArea.track(mouse) }
        onPositionChanged: function (mouse) { if (pressed) svArea.track(mouse) }
        onReleased: picker.commit()
      }

      function track(mouse) {
        picker.sat = Config.clamp01(mouse.x / svArea.width)
        picker.val = 1 - Config.clamp01(mouse.y / svArea.height)
      }
    }

    Rectangle {
      id: hueStrip
      width: parent.width
      height: Style.space(16)
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0000; color: "#ff0000" }
        GradientStop { position: 0.1667; color: "#ffff00" }
        GradientStop { position: 0.3333; color: "#00ff00" }
        GradientStop { position: 0.5000; color: "#00ffff" }
        GradientStop { position: 0.6667; color: "#0000ff" }
        GradientStop { position: 0.8333; color: "#ff00ff" }
        GradientStop { position: 1.0000; color: "#ff0000" }
      }

      Rectangle {
        x: picker.hue * hueStrip.width - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: parent.height + Style.space(4)
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Style.space(2))
        border.color: "#ffffff"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: function (mouse) { picker.setHue(mouse.x / hueStrip.width) }
        onPositionChanged: function (mouse) { if (pressed) picker.setHue(mouse.x / hueStrip.width) }
        onReleased: picker.commit()
      }
    }

    Item {
      width: parent.width
      height: hexField.implicitHeight

      Rectangle {
        id: preview
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        height: width
        radius: picker.radius
        color: picker.current
      }

      TextField {
        id: hexField
        anchors.left: preview.right
        anchors.leftMargin: Style.spacing.xs
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "#rrggbb"
        foreground: picker.foreground
        font.family: picker.fontFamily

        Binding {
          target: hexField.background
          property: "radius"
          value: picker.radius
        }
        // Typing breaks any binding on `text`, so it is assigned rather than bound.
        Component.onCompleted: hexField.text = picker.currentHex
        onAccepted: if (!picker.applyHex(text)) text = picker.currentHex

        Connections {
          target: picker
          function onCurrentHexChanged() { hexField.text = picker.currentHex }
        }
      }
    }

    Row {
      id: channels
      width: parent.width
      spacing: Style.spacing.xs

      readonly property real cell: (width - spacing * 2) / 3

      component Channel: Item {
        id: entry

        property string label: ""
        property real amount: 0
        property alias field: entryField

        width: channels.cell
        height: entryField.implicitHeight

        Text {
          id: entryLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: entry.label
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: picker.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        TextField {
          id: entryField
          anchors.left: entryLabel.right
          anchors.leftMargin: Style.spacing.xxs
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: TextInput.AlignHCenter
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator { bottom: 0; top: 255 }
          foreground: picker.foreground
          font.family: picker.fontFamily

          Binding {
            target: entryField.background
            property: "radius"
            value: picker.radius
          }
          Component.onCompleted: entryField.text = Config.channel(entry.amount)
          onAccepted: picker.setChannels()

          Connections {
            target: entry
            function onAmountChanged() { entryField.text = Config.channel(entry.amount) }
          }
        }
      }

      Channel { id: red; label: "R"; amount: picker.current.r }
      Channel { id: green; label: "G"; amount: picker.current.g }
      Channel { id: blue; label: "B"; amount: picker.current.b }
    }

    Item {
      width: parent.width
      height: Math.max(Style.space(20), resetButton.implicitHeight)

      Row {
        id: presets
        anchors.left: parent.left
        anchors.right: resetButton.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        readonly property real cell:
          (width - spacing * (Config.PRESETS.length - 1)) / Config.PRESETS.length

        Repeater {
          model: Config.PRESETS

          delegate: Rectangle {
            id: preset
            required property var modelData

            width: presets.cell
            height: width
            radius: width / 2
            color: preset.modelData
            border.width: presetMouse.containsMouse ? Math.max(1, Style.space(2)) : 0
            border.color: Color.popups.text

            MouseArea {
              id: presetMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: picker.applyHex(preset.modelData)
            }
          }
        }
      }

      // The snapshot revert glyph: putting a colour back is the same action shape.
      PanelActionButton {
        id: resetButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: Interface.Glyph.revert
        tooltipText: "Reset to default"
        foreground: picker.foreground
        fontFamily: picker.fontFamily
        onClicked: picker.applyHex(picker.config.defaultColorHex(picker.colorName))
      }
    }
  }
}

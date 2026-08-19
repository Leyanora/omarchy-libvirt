import QtQuick
import qs.Commons
import qs.Ui

// The settings view: the crash-toast switch, and the three state-light colours.
Column {
  id: settingsView

  property var config: null

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int radius: Style.cornerRadius

  width: parent.width
  spacing: Style.spacing.sm

  Toggle {
    width: parent.width
    // Toggle hardcodes Style.cornerRadius; the floor is what keeps it off square.
    radius: settingsView.radius
    label: "Suppress qemu crash notifications"
    description: "Also silences a QEMU crash that happens mid-run."
    checked: settingsView.config.suppressCrashToasts
    foreground: settingsView.foreground
    fontFamily: settingsView.fontFamily
    onClicked: settingsView.config.persist("suppressCrashToasts", !settingsView.config.suppressCrashToasts)
  }

  // Boxed off: three parts of one setting, which a bare hex field would not read as.
  BorderSurface {
    width: parent.width
    height: colorGroup.implicitHeight + Style.spacing.sm * 2
    radius: settingsView.radius
    color: "transparent"
    borderSpec: Border.flat(Qt.darker(settingsView.foreground, 1.8), Math.max(1, Style.space(1)))

    Column {
      id: colorGroup
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.sm
      spacing: Style.spacing.xs

      PanelSectionHeader {
        text: "State light colours"
        foreground: settingsView.foreground
        fontFamily: settingsView.fontFamily
      }

      Repeater {
        model: settingsView.config.colorSettings

        delegate: Item {
          id: colorRow
          required property var modelData

          width: colorGroup.width
          height: Math.max(swatch.height, colorField.implicitHeight)

          Rectangle {
            id: swatch
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12)
            height: width
            radius: width / 2
            color: settingsView.config.colorValue(colorRow.modelData.name)
          }

          Text {
            id: colorLabel
            anchors.left: swatch.right
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(64)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: colorRow.modelData.label
            color: Color.popups.text
            font.family: settingsView.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: colorField
            anchors.left: colorLabel.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: settingsView.config.colorHex(colorRow.modelData.name)
            placeholderText: "#rrggbb"
            foreground: settingsView.foreground
            font.family: settingsView.fontFamily

            // TextField keeps radius on its background delegate, past an override's reach.
            Binding {
              target: colorField.background
              property: "radius"
              value: settingsView.radius
            }
            // Typing breaks the binding, so a rejected value is put back by hand.
            onAccepted: {
              if (!settingsView.config.persistColor(colorRow.modelData.name, text))
                text = settingsView.config.colorHex(colorRow.modelData.name)
            }

            Connections {
              target: settingsView
              function onVisibleChanged() {
                if (settingsView.visible)
                  colorField.text = settingsView.config.colorHex(colorRow.modelData.name)
              }
            }
          }
        }
      }
    }
  }
}

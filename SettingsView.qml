import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface

// The settings view: the crash-toast switch, and the three state-light colours.
Column {
  id: settingsView

  property var config: null

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int radius: Style.cornerRadius

  property string expandedColor: ""

  signal colorExpandToggled(string name)

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

  // Boxed off: three parts of one setting, which bare rows would not read as.
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

          readonly property string colorName: colorRow.modelData.name
          readonly property bool expanded: settingsView.expandedColor === colorRow.colorName

          width: colorGroup.width
          height: frame.height

          // Seeded on expand, never bound: hue has to survive a drag to grey.
          function seed() {
            if (colorRow.expanded)
              picker.setFrom(settingsView.config.colorValue(colorRow.colorName))
          }

          onExpandedChanged: seed()
          Component.onCompleted: seed()

          // The border is what makes an expanded row read as one object.
          BorderSurface {
            id: frame
            width: parent.width
            // The pane's own top margin is in the sum too, or the bottom edge clips.
            height: header.height + (colorRow.expanded
              ? pickerPane.height + Style.spacing.xs + Style.spacing.sm + frame.borderTop * 2
              : 0)
            radius: settingsView.radius
            // Filled like Toggle at rest, so the header and the picker read as one card.
            color: colorRow.expanded
              ? Style.normalFillFor(settingsView.foreground, Color.accent)
              : "transparent"
            borderSpec: colorRow.expanded
              ? Border.flat(Qt.darker(settingsView.foreground, 1.8), Math.max(1, Style.space(1)))
              : Border.none()

            Item {
              id: header
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: frame.borderTop
              height: Math.max(Style.space(26), paletteButton.implicitHeight)

              Rectangle {
                id: swatch
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(12)
                height: width
                radius: width / 2
                // Follows the drag while open; the persisted value only lands on release.
                color: colorRow.expanded
                  ? picker.current
                  : settingsView.config.colorValue(colorRow.colorName)
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

              Text {
                anchors.left: colorLabel.right
                anchors.leftMargin: Style.spacing.sm
                anchors.right: paletteButton.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: colorRow.expanded
                  ? picker.currentHex
                  : settingsView.config.colorHex(colorRow.colorName)
                color: Qt.darker(Color.popups.text, 1.3)
                font.family: settingsView.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              PanelActionButton {
                id: paletteButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: Interface.Glyph.palette
                tooltipText: colorRow.expanded ? "Close picker" : "Pick a colour"
                foreground: settingsView.foreground
                fontFamily: settingsView.fontFamily
                bordered: colorRow.expanded
                onClicked: settingsView.colorExpandToggled(colorRow.colorName)
              }
            }

            // Frame carries the fill; this is the layout box the picker sits in.
            Item {
              id: pickerPane
              anchors.top: header.bottom
              anchors.topMargin: Style.spacing.xs
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: frame.borderLeft
              anchors.rightMargin: frame.borderRight
              visible: colorRow.expanded
              height: picker.implicitHeight + Style.spacing.sm * 2

              ColorPicker {
                id: picker
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.sm
                config: settingsView.config
                colorName: colorRow.colorName
                foreground: settingsView.foreground
                fontFamily: settingsView.fontFamily
                radius: settingsView.radius
              }
            }
          }
        }
      }
    }
  }
}

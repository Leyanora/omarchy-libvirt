import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Interface.js" as Interface

// The settings view: connection, the behaviour switches, and the state-light colours.
Column {
  id: settingsView

  property var config: null

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property int radius: Style.cornerRadius

  property string expandedColor: ""

  // The polled names, for the bar picker; handed in so the view never reads the service.
  property var domainNames: []

  signal colorExpandToggled(string name)
  // Focus is handed back explicitly: dropping it would leave no item holding keys.
  signal keysReleased()

  width: parent.width
  spacing: Style.spacing.sm

  // Escape propagates up from whichever control holds the keys, and hands them back.
  Keys.onEscapePressed: settingsView.keysReleased()

  SettingsGroup {
    width: parent.width
    radius: settingsView.radius
    title: "Connection"
    foreground: settingsView.foreground
    fontFamily: settingsView.fontFamily

    // An allowlist, not a text field: this value ends up in every virsh call.
    Dropdown {
      id: connection
      width: parent.width
      label: "libvirt URI"
      value: settingsView.config.uri
      options: settingsView.config.connectionOptions
      foreground: Commons.Color.popups.text
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onChanged: function (value) { settingsView.config.persistUri(value) }
    }

    NumberField {
      label: "Poll seconds"
      value: settingsView.config.interval
      from: 2
      to: 300
      foreground: settingsView.foreground
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onModified: function (value) { settingsView.config.persistInterval(value) }
    }

    NumberField {
      label: "Usage seconds"
      value: settingsView.config.statsInterval
      from: 1
      to: 60
      foreground: settingsView.foreground
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onModified: function (value) { settingsView.config.persistStatsInterval(value) }
    }
  }

  SettingsGroup {
    width: parent.width
    radius: settingsView.radius
    title: "Behaviour"
    foreground: settingsView.foreground
    fontFamily: settingsView.fontFamily

    Repeater {
      model: settingsView.config.behaviourSettings

      delegate: Toggle {
        required property var modelData

        width: parent.width
        // Toggle hardcodes Style.cornerRadius; the floor is what keeps it off square.
        radius: settingsView.radius
        label: modelData.label
        description: modelData.description
        checked: settingsView.config.flag(modelData.name)
        foreground: settingsView.foreground
        fontFamily: settingsView.fontFamily
        onClicked: settingsView.config.persist(modelData.name,
          !settingsView.config.flag(modelData.name))
      }
    }

    // Names are matched against parsed stats only, so no allowlist: none reaches argv.
    MultiSelect {
      width: parent.width
      visible: settingsView.config.barStats
      label: "Domains in the bar"
      noSelectionText: "All running"
      emptyText: "No domains defined"
      values: settingsView.config.barDomains
      options: settingsView.domainNames
      foreground: Commons.Color.popups.text
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onChanged: function (values) { settingsView.config.persist("barDomains", values) }
    }
  }

  SettingsGroup {
    width: parent.width
    visible: settingsView.config.barStats
    radius: settingsView.radius
    title: "Bar labels"
    foreground: settingsView.foreground
    fontFamily: settingsView.fontFamily

    Toggle {
      width: parent.width
      label: "Show domain names"
      description: "Turn off for just the icon and usage figures."
      checked: settingsView.config.barShowNames
      foreground: settingsView.foreground
      fontFamily: settingsView.fontFamily
      onClicked: settingsView.config.persist("barShowNames", !settingsView.config.barShowNames)
    }

    Toggle {
      width: parent.width
      label: "Show memory usage"
      description: "RAM in use / guest total, excluding reclaimable cache when reported."
      checked: settingsView.config.barMemory
      foreground: settingsView.foreground
      fontFamily: settingsView.fontFamily
      onClicked: settingsView.config.persist("barMemory", !settingsView.config.barMemory)
    }

    NumberField {
      visible: settingsView.config.barShowNames
      label: "Maximum name characters"
      value: settingsView.config.barNameLength
      from: 1
      to: 40
      foreground: settingsView.foreground
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onModified: function (value) { settingsView.config.persistBarNameLength(value) }
    }

    Dropdown {
      id: aliasDomain
      property string selectedDomain: ""
      width: parent.width
      visible: settingsView.config.barShowNames && settingsView.domainNames.length > 0
      label: "Domain to label"
      options: settingsView.domainNames.map(function (name) { return { value: name, label: name } })
      value: settingsView.domainNames.indexOf(selectedDomain) >= 0
        ? selectedDomain : (settingsView.domainNames[0] || "")
      foreground: Commons.Color.popups.text
      accent: Commons.Color.accent
      fontFamily: settingsView.fontFamily
      onChanged: function (value) { selectedDomain = value }
    }

    TextField {
      width: parent.width
      visible: aliasDomain.visible
      placeholderText: "Bar alias (empty uses the domain name)"
      text: settingsView.config.barAliases["d:" + aliasDomain.value] || ""
      foreground: settingsView.foreground
      font.family: settingsView.fontFamily
      onEditingFinished: {
        if (aliasDomain.value !== "") settingsView.config.persistBarAlias(aliasDomain.value, text)
      }
      onAccepted: settingsView.keysReleased()
    }
  }

  SettingsGroup {
    width: parent.width
    radius: settingsView.radius
    title: "State light colours"
    foreground: settingsView.foreground
    fontFamily: settingsView.fontFamily

    Repeater {
      model: settingsView.config.colorSettings

      delegate: Item {
        id: colorRow
        required property var modelData

        readonly property string colorName: colorRow.modelData.name
        readonly property bool expanded: settingsView.expandedColor === colorRow.colorName

        width: parent.width
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
            ? Style.normalFillFor(settingsView.foreground, Commons.Color.accent)
            : "transparent"
          borderSpec: colorRow.expanded
            ? Border.flat(Qt.darker(settingsView.foreground, 1.8), Math.max(1, Style.space(1)))
            : Border.none()

          // The card grows into the picker rather than snapping open under the cursor.
          Behavior on height {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
          }

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
              color: Commons.Color.popups.text
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
              color: Qt.darker(Commons.Color.popups.text, 1.3)
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

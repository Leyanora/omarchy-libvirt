import QtQuick
import qs.Commons
import qs.Ui
import "Interface.js" as Interface

// Three views in one Column, gated by `listView` — there is no StackView.
PopupCard {
  id: popup

  property var service: null
  property var config: null
  property var crashWatch: null

  property bool settingsOpen: false
  property string snapshotDomain: ""
  property string expandedDomain: ""
  property string expandedColor: ""

  // Neither sub-view: list-view elements gate on this, not on the sub-views.
  readonly property bool listView: snapshotDomain === "" && !settingsOpen

  signal backRequested()
  signal settingsRequested()
  signal snapshotsRequested(string name)
  signal consoleRequested(string name)
  signal expandToggled(string name)
  signal colorExpandToggled(string name)
  signal managerRequested()

  // Wider in settings: Toggle elides its label and never wraps it.
  contentWidth: popup.fittedContentWidth(Style.space(popup.settingsOpen ? 400 : 340))
  contentHeight: popup.fittedContentHeight(column.implicitHeight)

  readonly property string fontFamily: popup.bar ? popup.bar.fontFamily : Style.font.family
  readonly property color foreground: popup.bar ? popup.bar.foreground : Color.popups.text
  readonly property color urgent: popup.bar ? popup.bar.urgent : Color.urgent

  Column {
    id: column
    anchors.fill: parent
    spacing: Style.spacing.sm

    Item {
      width: parent.width
      implicitHeight: Math.max(title.implicitHeight, headerActions.implicitHeight)

      PanelActionButton {
        id: backButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: !popup.listView
        iconText: Interface.Glyph.back
        tooltipText: "Back"
        foreground: popup.foreground
        fontFamily: popup.fontFamily
        onClicked: popup.backRequested()
      }

      // PlainText on every Text: AutoText would parse `<` in a domain name as markup.
      Text {
        id: title
        anchors.left: backButton.visible ? backButton.right : parent.left
        anchors.leftMargin: backButton.visible ? Style.spacing.xs : 0
        anchors.right: headerActions.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: popup.settingsOpen
          ? "Settings"
          : (popup.snapshotDomain !== "" ? popup.snapshotDomain : "Virtual machines")
        color: Color.popups.text
        font.family: popup.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      // A Row skips invisible children, so hidden buttons leave no gap.
      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          visible: popup.listView
          iconText: Interface.Glyph.settings
          tooltipText: "Settings"
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          onClicked: popup.settingsRequested()
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          visible: !popup.settingsOpen
          iconText: Interface.Glyph.refresh
          tooltipText: "Refresh"
          foreground: popup.foreground
          fontFamily: popup.fontFamily
          enabled: !popup.service.busy
          onClicked: {
            if (popup.snapshotDomain !== "") popup.service.fetchSnapshots(popup.snapshotDomain)
            else popup.service.refresh()
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: popup.listView
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: Interface.connectionLabel(popup.service.connectionDown)
      color: popup.service.connectionDown ? popup.urgent : Qt.darker(Color.popups.text, 1.4)
      font.family: popup.fontFamily
      font.pixelSize: Style.font.caption

      MouseArea {
        id: connectionMouse
        anchors.fill: parent
        hoverEnabled: true

        PanelToolTip {
          visible: connectionMouse.containsMouse
          text: Interface.plain(popup.config.uri)
          fontFamily: popup.fontFamily
        }
      }
    }

    Text {
      width: parent.width
      visible: popup.snapshotDomain !== ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: "Snapshots"
      color: Qt.darker(Color.popups.text, 1.4)
      font.family: popup.fontFamily
      font.pixelSize: Style.font.caption
    }

    PanelSeparator {
      foreground: popup.foreground
    }

    DomainList {
      width: parent.width
      visible: popup.service.domains.length > 0 && popup.listView
      service: popup.service
      config: popup.config
      foreground: popup.foreground
      fontFamily: popup.fontFamily
      urgent: popup.urgent
      expandedDomain: popup.expandedDomain
      onConsoleRequested: function (name) { popup.consoleRequested(name) }
      onSnapshotsRequested: function (name) { popup.snapshotsRequested(name) }
      onExpandToggled: function (name) { popup.expandToggled(name) }
    }

    Text {
      width: parent.width
      visible: popup.service.domains.length === 0 && popup.service.lastError === "" && popup.listView
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "No domains defined on this connection."
      color: Color.popups.text
      opacity: 0.7
      font.family: popup.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    SettingsView {
      visible: popup.settingsOpen
      config: popup.config
      foreground: popup.foreground
      fontFamily: popup.fontFamily
      radius: popup.config.radius
      expandedColor: popup.expandedColor
      onColorExpandToggled: function (name) { popup.colorExpandToggled(name) }
    }

    SnapshotView {
      visible: popup.snapshotDomain !== ""
      service: popup.service
      domain: popup.snapshotDomain
      foreground: popup.foreground
      fontFamily: popup.fontFamily
      urgent: popup.urgent
      radius: popup.config.radius
    }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: Interface.errorText(popup.config.error, popup.service.lastError,
        popup.service.actionError, popup.crashWatch.error)
      color: popup.urgent
      font.family: popup.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    PanelSeparator {
      visible: popup.config.manager !== "" && popup.listView
      foreground: popup.foreground
    }

    Rectangle {
      width: parent.width
      height: Style.space(28)
      radius: popup.config.radius
      visible: popup.config.manager !== "" && popup.listView
      color: managerMouse.containsMouse ? Style.hoverFill : "transparent"

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Interface.Glyph.manager + "  Open virt-manager"
        color: Color.popups.text
        font.family: popup.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: managerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.managerRequested()
      }
    }
  }
}

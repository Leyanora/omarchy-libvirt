import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Interface.js" as Interface

// Three views in one Column, gated by `listView` — there is no StackView.
// KeyboardPanel, not PopupCard: an xdg-popup only gets keys after a click routes
// focus through its parent surface, so the arrows would never arrive.
KeyboardPanel {
  id: popup

  property var service: null
  property var config: null

  property bool settingsOpen: false
  property string snapshotDomain: ""
  property string expandedDomain: ""
  property string expandedColor: ""

  // Filtered by the root, which also owns the cursor index into it.
  property var domains: []
  property int cursorIndex: -1
  property string filterText: ""

  // Neither sub-view: list-view elements gate on this, not on the sub-views.
  readonly property bool listView: snapshotDomain === "" && !settingsOpen

  // A filter that has emptied the list must stay reachable to be cleared again.
  readonly property bool filterable: popup.listView
    && (popup.service.domains.length >= Interface.FILTER_MIN || popup.filterText !== "")

  signal backRequested()
  signal settingsRequested()
  signal snapshotsRequested(string name)
  signal consoleRequested(string name)
  signal expandToggled(string name)
  signal colorExpandToggled(string name)
  signal managerRequested()
  signal filterChanged(string text)
  signal cursorRequested(int index)
  signal cursorNameRequested(string name)

  signal keyMove(int delta)
  signal keyHorizontal(int delta)
  signal keyActivate()
  signal keyDelete()
  signal keyText(string text)
  signal escapePressed()

  // Wider in settings: Toggle elides its label and never wraps it.
  contentWidth: popup.fittedContentWidth(Style.space(popup.settingsOpen ? 400 : 340))
  contentHeight: popup.fittedContentHeight(column.implicitHeight)
  focusTarget: keyCatcher

  readonly property string fontFamily: popup.bar ? popup.bar.fontFamily : Style.font.family
  readonly property color foreground: popup.bar ? popup.bar.foreground : Commons.Color.popups.text
  readonly property color urgent: popup.bar ? popup.bar.urgent : Commons.Color.urgent

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    // One rule for every editor in every view: the moment a control inside takes
    // focus the catcher loses it, and the keys are that control's until it hands back.
    blocked: !keyCatcher.activeFocus

    onMoveRequested: function (dx, dy) {
      if (dy !== 0) popup.keyMove(dy)
      if (dx !== 0) popup.keyHorizontal(dx)
    }
    onActivateRequested: popup.keyActivate()
    // The catcher swallows Tab, so the settings controls are stepped into by hand.
    onTabRequested: function (direction) {
      var next = keyCatcher.nextItemInFocusChain(direction > 0)
      if (next) next.forceActiveFocus()
    }
    onDeleteRequested: popup.keyDelete()
    onCloseRequested: popup.escapePressed()
    // `/` is this component's own field, so it never has to reach the root and back.
    onTextKey: function (text) {
      if (text === "/" && popup.filterable) filterField.forceActiveFocus()
      else popup.keyText(text)
    }

    ScrollableColumn {
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
          color: Commons.Color.popups.text
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
        text: Interface.connectionLabel(popup.service.connectionDown,
          popup.service.backendMissing)
        color: popup.service.connectionDown ? popup.urgent : Qt.darker(Commons.Color.popups.text, 1.4)
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
        color: Qt.darker(Commons.Color.popups.text, 1.4)
        font.family: popup.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator {
        foreground: popup.foreground
      }

      TextField {
        id: filterField
        width: parent.width
        visible: popup.filterable
        placeholderText: Interface.Glyph.search + "  Filter domains"
        text: popup.filterText
        foreground: popup.foreground
        font.family: popup.fontFamily
        onTextChanged: popup.filterChanged(text)
        // Focus is handed back explicitly: dropping it would leave no item holding keys.
        onAccepted: keyCatcher.forceActiveFocus()
        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
      }

      DomainList {
        width: parent.width
        visible: popup.domains.length > 0 && popup.listView
        service: popup.service
        config: popup.config
        domains: popup.domains
        cursorIndex: popup.cursorIndex
        foreground: popup.foreground
        fontFamily: popup.fontFamily
        urgent: popup.urgent
        expandedDomain: popup.expandedDomain
        onConsoleRequested: function (name) { popup.consoleRequested(name) }
        onSnapshotsRequested: function (name) { popup.snapshotsRequested(name) }
        onExpandToggled: function (name) { popup.expandToggled(name) }
        onCursorRequested: function (name) { popup.cursorNameRequested(name) }
      }

      // Three empty states, and they are not the same state: not polled yet, nothing
      // defined, nothing matching.
      Text {
        width: parent.width
        visible: popup.domains.length === 0 && popup.service.lastError === "" && popup.listView
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: !popup.service.polled
          ? "Asking libvirt…"
          : (popup.filterText !== ""
            ? "No domains match that filter."
            : "No domains defined on this connection.")
        color: Commons.Color.popups.text
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
        domainNames: popup.service.domains.map(function (domain) { return domain.name })
        onColorExpandToggled: function (name) { popup.colorExpandToggled(name) }
        onKeysReleased: keyCatcher.forceActiveFocus()
      }

      SnapshotView {
        visible: popup.snapshotDomain !== ""
        service: popup.service
        domain: popup.snapshotDomain
        foreground: popup.foreground
        fontFamily: popup.fontFamily
        urgent: popup.urgent
        radius: popup.config.radius
        cursorIndex: popup.cursorIndex
        onCursorRequested: function (index) { popup.cursorRequested(index) }
        onKeysReleased: keyCatcher.forceActiveFocus()
      }

      Notice {
        width: parent.width
        model: Interface.notice(popup.config.error, popup.service.lastError,
          popup.service.actionError, popup.service.backendMissing, popup.service.missingConsole,
          popup.config.uri)
        radius: popup.config.radius
        foreground: popup.foreground
        urgent: popup.urgent
        fontFamily: popup.fontFamily
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
          color: Commons.Color.popups.text
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
}

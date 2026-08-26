import QtQuick
import qs.Commons

// The domain rows, sized to their content up to a cap and scrolling past it.
ListView {
  id: domainList

  property var service: null
  property var config: null

  // Already filtered by the root, which also owns the cursor index into it.
  property var domains: []
  property int cursorIndex: -1

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color urgent: Color.urgent

  property string expandedDomain: ""

  signal consoleRequested(string name)
  signal snapshotsRequested(string name)
  signal expandToggled(string name)
  signal cursorRequested(string name)

  height: Math.min(contentHeight, Style.space(300))
  clip: true
  interactive: contentHeight > height
  boundsBehavior: Flickable.StopAtBounds
  model: domainList.domains

  // Follows the keyboard cursor out of view; a mouse-driven cursor is already visible.
  onCursorIndexChanged: if (cursorIndex >= 0) positionViewAtIndex(cursorIndex, ListView.Contain)

  delegate: DomainRow {
    required property int index

    service: domainList.service
    foreground: domainList.foreground
    fontFamily: domainList.fontFamily
    urgent: domainList.urgent
    radius: domainList.config.radius
    colorRunning: domainList.config.colorRunning
    colorPaused: domainList.config.colorPaused
    colorStopped: domainList.config.colorStopped
    showSnapshots: domainList.config.showSnapshots
    consoleEnabled: domainList.config.consoleCommand !== ""
    expanded: domainList.expandedDomain === domainName
    hasCursor: domainList.cursorIndex === index
    onConsoleRequested: function (name) { domainList.consoleRequested(name) }
    onSnapshotsRequested: function (name) { domainList.snapshotsRequested(name) }
    onExpandToggled: function (name) { domainList.expandToggled(name) }
    onCursorRequested: function (name) { domainList.cursorRequested(name) }
  }
}

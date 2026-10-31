import QtQuick

// Settings can exceed the available panel height on smaller displays.
Flickable {
  id: scroll
  default property alias content: rows.data
  property alias spacing: rows.spacing

  implicitHeight: rows.implicitHeight
  contentHeight: rows.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  property Item layout: Column {
    id: rows
    parent: scroll.contentItem
    width: scroll.width
  }
}

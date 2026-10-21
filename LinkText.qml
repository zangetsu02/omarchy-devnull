import QtQuick
import qs.Commons

// Text that goes somewhere: a name, a handle, a hash. Under the pointer it
// takes `hoverColor` and an underline, so it reads as a link before the click.
// The MouseArea keeps the click, so the row behind it does not act as well.
Mono {
  id: root

  property color restColor: Color.foreground
  property color hoverColor: Color.foreground
  readonly property bool hovered: area.containsMouse
  signal clicked()

  color: hovered ? hoverColor : restColor
  font.underline: hovered

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}

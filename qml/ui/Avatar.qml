import QtQuick
import qs.Commons

// A round GitHub avatar, with the initial showing while it loads or when it
// cannot. `ring` draws the author's lane around it, as profiles do.
Item {
  id: root

  property string source: ""
  property string name: ""
  property real size: Style.space(32)
  property color ring: "transparent"
  // Lightens under the pointer when the avatar leads somewhere.
  property bool clickable: false
  signal clicked()

  readonly property real ringWidth: ring.a > 0 ? 2 : 0
  readonly property real gap: ringWidth > 0 ? 2 : 0

  implicitWidth: size + (ringWidth + gap) * 2
  implicitHeight: implicitWidth

  Rectangle {
    anchors.fill: parent
    visible: root.ringWidth > 0
    radius: width / 2
    color: "transparent"
    border.width: root.ringWidth
    border.color: root.ring
  }

  opacity: clickable && area.containsMouse ? 0.75 : 1
  Behavior on opacity { NumberAnimation { duration: 120 } }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Picture {
    id: picture
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    source: root.source

    Mono {
      anchors.centerIn: parent
      visible: !picture.ready
      text: (root.name || "?").charAt(0).toUpperCase()
      font.pixelSize: root.size * 0.42
      font.bold: true
    }
  }
}

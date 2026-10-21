import QtQuick
import Quickshell.Widgets
import qs.Commons

// A round GitHub avatar, with the initial on a wash while it loads or when it
// cannot. `ring` draws the author's lane around it, as profiles do.
Item {
  id: root

  property string source: ""
  property string name: ""
  property real size: Style.space(32)
  property color ring: "transparent"
  property color wash: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)

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

  ClippingRectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.wash

    Text {
      anchors.centerIn: parent
      visible: picture.status !== Image.Ready
      text: (root.name || "?").charAt(0).toUpperCase()
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: root.size * 0.42
      font.bold: true
    }

    Image {
      id: picture
      anchors.fill: parent
      source: root.source
      // GitHub serves any size; asking for twice the box keeps it sharp on HiDPI.
      sourceSize: Qt.size(root.size * 2, root.size * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }
  }
}

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

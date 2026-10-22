import QtQuick
import qs.Commons

// The two slashes dev-null.sh uses as its mark. Filled when something is
// unread, outlined when it is quiet, crossed when the pairing is gone — the
// same at-a-glance rule the other bar widgets use.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground
  property bool filled: false
  property bool crossed: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1, Math.round(iconSize * 0.13))

  Repeater {
    model: 2
    Rectangle {
      width: root.stroke
      height: Math.round(root.iconSize * 0.78)
      radius: width / 2
      color: root.color
      opacity: root.filled ? 1 : 0.65
      antialiasing: true
      rotation: 20
      x: Math.round(root.iconSize * (index === 0 ? 0.3 : 0.56))
      y: Math.round(root.iconSize * 0.11)
    }
  }

  // A line through it means the device is no longer approved.
  Rectangle {
    visible: root.crossed
    width: Math.round(root.iconSize * 1.05)
    height: root.stroke
    radius: height / 2
    color: root.color
    antialiasing: true
    rotation: -45
    anchors.centerIn: parent
  }
}

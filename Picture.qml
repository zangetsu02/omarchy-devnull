import QtQuick
import Quickshell.Widgets
import qs.Commons

// A remote picture clipped to rounded corners, on a faint wash while it loads
// or when it cannot. Avatars, commit images and link cards all draw with it.
ClippingRectangle {
  id: root

  property alias source: image.source
  property alias fillMode: image.fillMode
  readonly property bool ready: image.status === Image.Ready

  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

  Image {
    id: image
    anchors.fill: parent
    // Decoded at twice the box so it stays sharp on HiDPI without holding the
    // full-size original in memory.
    sourceSize: Qt.size(root.width * 2, root.height * 2)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
  }
}

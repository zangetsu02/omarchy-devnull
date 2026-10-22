import QtQuick
import qs.Commons
import "../ui"

// A commit's pictures at full size, over the whole window. ← → (or h l) step
// through them, enter opens the one in front in the browser, esc or a click
// outside closes. FullPanel routes the keys here while it is open.
Rectangle {
  id: root

  required property var view
  property var images: []
  property int index: 0
  readonly property bool open: images.length > 0
  readonly property var current: open ? images[index] : null

  function show(pictures, at) {
    images = pictures
    index = Math.max(0, Math.min(at, pictures.length - 1))
  }
  function close() { images = [] }
  function step(by) { if (open) index = (index + by + images.length) % images.length }

  // Answers true when it used the key, so the view does not act on it too.
  function handleKey(event) {
    if (!open) return false
    if (event.key === Qt.Key_Escape) close()
    else if (event.key === Qt.Key_Left || event.text === "h") step(-1)
    else if (event.key === Qt.Key_Right || event.text === "l") step(1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) view.openOnSite(current.url)
    return true
  }

  visible: open
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.94)

  TapHandler { onTapped: root.close() }

  Image {
    id: picture
    anchors.fill: parent
    anchors.margins: Style.space(48)
    anchors.bottomMargin: Style.space(72)
    source: root.current ? root.current.url : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    // A click on the picture itself must not close the viewer.
    TapHandler { onTapped: {} }
  }

  Mono {
    anchors.centerIn: picture
    visible: picture.status === Image.Loading
    text: "loading…"
    color: Color.muted
  }

  Mono {
    anchors.centerIn: picture
    visible: picture.status === Image.Error
    text: "fatal: could not load this picture"
    color: root.view.destructive
  }

  Arrow { visible: root.images.length > 1; anchors.left: parent.left; text: "‹"; onTapped: root.step(-1) }
  Arrow { visible: root.images.length > 1; anchors.right: parent.right; text: "›"; onTapped: root.step(1) }

  Mono {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(24)
    width: Math.min(implicitWidth, parent.width - Style.space(48))
    elide: Text.ElideRight
    color: Color.muted
    text: (root.images.length > 1 ? (root.index + 1) + " / " + root.images.length + "   " : "")
      + (root.current && root.current.alt ? root.current.alt + "   " : "")
      + (root.images.length > 1 ? "← → step   " : "") + "enter opens it   esc closes"
  }

  component Arrow: Mono {
    signal tapped()
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Style.space(16)
    rightPadding: Style.space(16)
    font.pixelSize: Style.font.subtitle * 3
    color: arrowHover.hovered ? Color.foreground : Color.muted
    HoverHandler { id: arrowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: parent.tapped() }
  }
}

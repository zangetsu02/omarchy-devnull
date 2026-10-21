import QtQuick
import qs.Commons

// A quiet action under a commit: an icon, an optional label, a wash on hover.
// `active` lights it in `activeColor`, e.g. a star you gave.
Rectangle {
  id: root

  property string icon: ""
  property string label: ""
  property bool active: false
  property color activeColor: Color.accent
  property color restColor: Color.muted
  signal clicked()

  readonly property bool hovered: hover.hovered
  readonly property color ink: active ? activeColor : (hovered ? Color.foreground : restColor)

  implicitWidth: content.implicitWidth + Style.space(12)
  implicitHeight: content.implicitHeight + Style.space(6)
  radius: Style.space(5)
  color: hovered ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(5)
    Mono { visible: root.icon !== ""; text: root.icon; color: root.ink; font.pixelSize: Style.font.body }
    Mono { visible: root.label !== ""; text: root.label; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}

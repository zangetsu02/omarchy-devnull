import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One commit in its own bordered box: who, hash, age, the body, the counts.
// The popup and the full view draw the same card; only `bodyLines` differs.
BorderSurface {
  id: root

  required property var row
  property bool selected: false
  property int bodyLines: 2
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  property color dim: Color.muted
  // Bumped by the owner every minute so the age keeps up without a refetch.
  property double now: Date.now()

  signal clicked()

  readonly property bool lit: selected || hover.hovered
  readonly property real pad: Style.space(8)

  implicitHeight: content.implicitHeight + pad * 2
  radius: Style.cornerRadius
  color: lit ? Style.hoverFillFor(foreground, Color.accent) : Style.normalFillFor(foreground, Color.accent)
  borderSpec: Border.controlSpec(lit ? "hover" : "normal", foreground, Color.accent)

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }

  Column {
    id: content
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Style.space(4)

    Row {
      spacing: Style.space(8)
      Text {
        text: root.row.handle
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        text: root.row.hash
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        text: Model.ageFor(root.row.created, root.now) + (root.row.pending ? "  · held" : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      width: parent.width
      text: root.row.body !== "" ? root.row.body : "(empty commit)"
      color: root.row.body !== "" ? root.foreground : root.dim
      font.italic: root.row.body === ""
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      maximumLineCount: root.bodyLines
      elide: Text.ElideRight
    }

    Text {
      text: (root.row.starred ? "★ " : "☆ ") + root.row.stars + "    ↩ " + root.row.replies
      color: root.row.starred ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}

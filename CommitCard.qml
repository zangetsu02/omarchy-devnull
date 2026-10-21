import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One commit in its own bordered box: who, hash, age, the body, the counts.
// Used by the bar popup; the full view draws commits as LogRow instead.
BorderSurface {
  id: root

  required property var row
  property int bodyLines: 2
  property color foreground: Color.foreground
  // Bumped by the owner every minute so the age keeps up without a refetch.
  property double now: Date.now()

  signal clicked()

  readonly property bool lit: hover.hovered
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
      Mono {
        text: root.row.handle
        color: root.foreground
        font.bold: true
      }
      Mono {
        text: root.row.hash
        color: Color.accent
      }
      Mono {
        text: Model.ageFor(root.row.created, root.now) + (root.row.pending ? "  · held" : "")
        color: Color.muted
      }
    }

    Mono {
      width: parent.width
      text: root.row.body !== "" ? root.row.body : "(empty commit)"
      color: root.row.body !== "" ? root.foreground : Color.muted
      font.italic: root.row.body === ""
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      maximumLineCount: root.bodyLines
      elide: Text.ElideRight
    }

    Mono {
      text: (root.row.starred ? "★ " : "☆ ") + root.row.stars + "    ↩ " + root.row.replies
      color: root.row.starred ? Color.accent : Color.muted
    }
  }
}

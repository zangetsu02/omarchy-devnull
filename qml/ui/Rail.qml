import QtQuick
import "../data/Model.js" as Model

// The graph rail, drawn as a terminal draws it: one glyph per line of text,
// the head marking this row and the tail carrying the lane down to the next.
//
// It replaces the rectangles the rail used to be, and it is one component
// rather than three copies, so the log, the notifications and the bar popup
// cannot drift apart.
Column {
  id: root

  // The grid this rail steps on.
  required property var metrics
  // How tall the row is, so the tail reaches its bottom.
  required property real rowHeight
  // The first glyph: the node, or the branch a reply hangs from.
  property string head: Model.GLYPHS.node
  property color headColor: "white"
  property color tailColor: "grey"
  // How many columns the rail occupies. A branch needs more than a bar.
  property int cells: 2

  spacing: 0

  Repeater {
    model: root.metrics.lineH > 0
      ? Math.max(1, Math.ceil(root.rowHeight / root.metrics.lineH))
      : 1
    Mono {
      required property int index
      width: root.metrics.cell * root.cells
      height: root.metrics.lineH
      font.pixelSize: root.metrics.size
      verticalAlignment: Text.AlignVCenter
      color: index === 0 ? root.headColor : root.tailColor
      text: index === 0 ? root.head : Model.rail("body", {})
    }
  }
}

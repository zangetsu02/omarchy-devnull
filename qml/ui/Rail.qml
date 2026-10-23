import QtQuick
import qs.Commons
import "../data/Model.js" as Model

// The graph rail, drawn as a terminal draws it: a head glyph marking this row
// and a lane carrying it down to the next.
//
// The lane is ONE text holding every line, not one text per line. A column of
// separate items leaves air between the boxes and `│` comes out dotted; inside
// a single text Qt lays the lines out at the font's own spacing and the glyphs
// touch, which is the whole reason a box-drawing bar exists.
Item {
  id: root

  required property var metrics
  property real rowHeight: parent ? parent.height - y : 0
  property string head: Model.GLYPHS.node
  property string tail: Model.rail("body", {})
  property color headColor: Color.foreground
  property color tailColor: Color.muted
  property int cells: 2

  readonly property int lines: metrics.lineH > 0
    ? Math.max(1, Math.ceil(rowHeight / metrics.lineH))
    : 1

  width: metrics.cell * cells
  height: rowHeight

  Mono {
    id: lane
    width: parent.width
    y: headGlyph.height
    color: root.tailColor
    font.pixelSize: root.metrics.size
    lineHeight: 1.0
    lineHeightMode: Text.ProportionalHeight
    textFormat: Text.PlainText
    text: {
      var out = []
      for (var i = 1; i < root.lines; i++) out.push(root.tail)
      return out.join("\n")
    }
  }

  Mono {
    id: headGlyph
    width: parent.width
    height: root.metrics.lineH
    verticalAlignment: Text.AlignVCenter
    color: root.headColor
    font.pixelSize: root.metrics.size
    textFormat: Text.PlainText
    text: root.head
  }
}

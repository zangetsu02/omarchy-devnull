import QtQuick
import qs.Commons
import "../data/Model.js" as Model

// The top or bottom border of a box-drawn pane, filling its width in whole
// character cells. A pane titles itself in its top border, as a TUI does.
Mono {
  id: root

  property string kind: "top"      // "top" or "bottom"
  property string title: ""
  property color lineColor: Color.muted

  readonly property real cell: grid.cell

  Metrics { id: grid }

  color: lineColor
  font.pixelSize: Style.font.body
  textFormat: Text.PlainText
  text: cell > 0 ? Model.frameLine(kind, width / cell, title) : ""
}

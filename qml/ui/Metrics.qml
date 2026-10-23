import QtQuick
import qs.Commons

// The character grid, measured once. Everything that lines up — the rail, the
// avatar, a header padded to a column count, a frame border — measures itself
// against these two numbers, so they are defined in exactly one place.
Item {
  id: root

  // The advance of one character. Meaningful only because the theme's font is
  // monospace: in a proportional face this would be the width of a zero and
  // nothing else would match it.
  readonly property real cell: metrics.advanceWidth("0")

  // The pitch the text really uses. Nothing in the plugin stretches its lines
  // (TextEdit has no lineHeight), so a rail stepping any wider than this draws
  // its bar dashed and drifts away from the line it belongs to.
  readonly property real lineH: metrics.height

  FontMetrics {
    id: metrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}

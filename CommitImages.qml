import QtQuick
import qs.Commons
import "Model.js" as Model

// The pictures under a commit. One keeps its proportions, capped in height;
// more are cropped into a two-column grid. A click opens them in the viewer.
Item {
  id: root

  required property var images
  required property var view
  property real maxHeight: Style.space(340)

  readonly property bool single: images.length === 1
  readonly property real gap: Style.space(4)
  readonly property real cell: (width - gap) / 2
  readonly property var fitted: single ? Model.fitImage(images[0], width, maxHeight) : ({ width: 0, height: 0 })

  visible: images.length > 0
  implicitHeight: single ? fitted.height : grid.implicitHeight

  Grid {
    id: grid
    columns: root.single ? 1 : 2
    spacing: root.gap

    Repeater {
      model: root.images
      Picture {
        id: tile
        required property var modelData
        required property int index
        width: root.single ? root.fitted.width : root.cell
        height: root.single ? root.fitted.height : Math.round(root.cell * 0.62)
        radius: Style.space(6)
        source: modelData.url
        // The border sits on top, so it frames the picture rather than the wash.
        Rectangle {
          anchors.fill: parent
          radius: tile.radius
          color: "transparent"
          border.width: tileHover.hovered ? 2 : 1
          border.color: tileHover.hovered ? root.view.primary : root.view.railColor
        }
        opacity: tileHover.hovered ? 0.9 : 1
        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.view.showImages(root.images, tile.index) }
      }
    }
  }
}

import QtQuick
import QtQuick.Controls
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// A list of commits on the graph rail, with a keyboard selection and a last
// line that pages. The log, the starred commits and a profile all use it.
ListView {
  id: root

  required property var view
  property var commits: []
  // What the last line says, from Model.listEnd.
  property string endLine: ""
  property bool hasMore: false
  signal loadMore()

  property string selectedId: ""
  readonly property int selectedIndex: {
    for (var i = 0; i < commits.length; i++) if (commits[i].id === selectedId) return i
    return commits.length > 0 ? 0 : -1
  }
  readonly property var selectedCommit: selectedIndex >= 0 ? commits[selectedIndex] : null

  function move(step) {
    if (commits.length === 0) return
    var next = Math.max(0, Math.min(commits.length - 1, selectedIndex + step))
    selectedId = commits[next].id
    positionViewAtIndex(next, ListView.Contain)
    if (next === commits.length - 1 && hasMore) loadMore()
  }

  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
  model: commits

  delegate: LogRow {
    required property int index
    required property var modelData
    width: root.width
    commit: modelData
    view: root.view
    selected: index === root.selectedIndex
    // Click moves the cursor, as in a terminal; double click is what `enter` is.
    // A click on the body selects text instead: TextEdit takes the grab there.
    TapHandler {
      onSingleTapped: root.selectedId = modelData.id
      onDoubleTapped: root.view.openCommit(modelData.id)
    }
  }

  footer: Item {
    width: root.width
    height: Style.space(52)
    Mono {
      anchors.centerIn: parent
      text: root.endLine
      color: text.indexOf("fatal:") === 0 ? root.view.destructive : Color.muted
    }
    HoverHandler { cursorShape: root.hasMore ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: if (root.hasMore) root.loadMore() }
  }
}

import QtQuick
import QtQuick.Controls
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// The staged commit at the top of the log: a hollow node in your lane that
// fills once there is something to commit, your avatar, the field, and the
// counter with the Commit button. Quoting puts the quoted commit under it.
Item {
  id: root

  required property var view
  readonly property alias field: field
  readonly property var me: view.me
  readonly property color lane: view.laneColor(me.lane || 0)
  readonly property int remaining: Model.charsLeft(view.composerText)
  readonly property bool ready: view.composerText.trim() !== "" && remaining >= 0
  readonly property real pad: Style.space(14)

  width: ListView.view ? ListView.view.width : 0
  // Hidden, it takes no room: a list header keeps its height otherwise, and a
  // height set from outside cannot know this formula.
  height: visible ? column.implicitHeight + pad * 2 : 0

  Metrics { id: grid }

  // The same character rail the commits below use, dotted until there is
  // something to commit. It was a column of little rectangles, which is the
  // one place the drawn graph outlived the grid.
  Rail {
    x: grid.cell
    y: root.pad
    metrics: grid
    cells: 2
    headColor: root.lane
    tailColor: root.lane
    head: root.ready ? Model.GLYPHS.nodeHere : Model.GLYPHS.node
    tail: Model.rail("staged", { ready: root.ready })
  }

  Avatar {
    id: avatar
    x: grid.cell * 2 - implicitWidth / 2
    y: root.pad
    size: grid.cell * 2
    ring: root.lane
    source: root.me.avatar_url || ""
    name: root.me.name || ""
  }

  Column {
    id: column
    x: grid.cell * 6
    y: root.pad
    width: root.width - x - Style.space(14)
    spacing: Style.space(8)

    TextArea {
      id: field
      width: column.width
      placeholderText: root.view.quoting ? "add your take…" : "What did you ship?"
      placeholderTextColor: Color.muted
      wrapMode: TextEdit.Wrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle + 2
      background: null
      padding: 0
      topPadding: Style.space(6)
      text: root.view.composerText
      onTextChanged: root.view.composerText = text
      Keys.onPressed: function (event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
          root.view.postComposer()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.view.leaveComposer()
          event.accepted = true
        }
      }
    }

    // What is being quoted, as it will appear under the commit.
    Rectangle {
      visible: !!root.view.quoting
      width: column.width
      height: quoted.implicitHeight + Style.space(14)
      color: "transparent"
      border.width: 1
      border.color: root.view.railColor
      Mono {
        id: quoted
        x: Style.space(10)
        y: Style.space(7)
        width: parent.width - Style.space(20)
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        text: root.view.quoting
          ? root.view.dimmed("❝ " + Model.rowFor(root.view.quoting).handle + " · esc drops the quote") + "<br>"
            + root.view.esc(Model.rowFor(root.view.quoting).body)
          : ""
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(12)
      Mono {
        anchors.verticalCenter: parent.verticalCenter
        text: root.remaining + "   ctrl+enter"
        color: root.remaining < 0 ? root.view.destructive : Color.muted
      }
      Rectangle {
        width: label.implicitWidth + Style.space(24)
        height: label.implicitHeight + Style.space(10)
        color: root.view.primary
        opacity: root.ready ? 1 : 0.45
        Mono {
          id: label
          anchors.centerIn: parent
          text: root.view.quoting ? "Quote" : "Commit"
          color: Color.background
          font.bold: true
        }
        HoverHandler { cursorShape: root.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: root.view.postComposer() }
      }
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    x: grid.cell * 6
    width: root.width - x
    height: 1
    color: root.view.railColor
  }
}

import QtQuick
import QtQuick.Controls
import qs.Commons
import "Model.js" as Model

// One commit as `git log --graph` would print it: a rail in the author's lane,
// then who, when and the hash, the body, and a row of actions. Replies use the
// same row one level in, behind a guide line instead of the rail, and nest
// through a Loader of this same file.
//
// It only talks to `view` (FullPanel): colours, fonts and every action go
// through it, so the row never reaches into the service behind it.
Item {
  id: root

  required property var commit
  required property var view
  property int depth: 0
  property bool selected: false
  // The lane of the commit drawn above, for the rail segment over the node.
  property color laneAbove: view.railColor

  readonly property var row: Model.rowFor(commit)
  readonly property color lane: view.laneColor(row.lane)
  readonly property bool topLevel: depth === 0
  readonly property var thread: view.threadFor(row.id)
  readonly property real railWidth: top ? Style.space(30) : Style.space(16)
  readonly property real pad: Style.space(8)
  readonly property string age: Model.ageFor(row.created, view.now)

  implicitHeight: body.implicitHeight + (top ? pad * 2 : pad)

  Rectangle {
    anchors.fill: parent
    visible: root.selected
    color: Style.selectedFillFor(root.view.foreground, Color.accent)
  }

  // --- The rail ---------------------------------------------------------------

  RailSegment { visible: root.topLevel; height: node.y; color: root.laneAbove }
  RailSegment { visible: root.topLevel; y: node.y + node.height; height: root.height - y; color: root.lane }

  Rectangle {
    id: node
    visible: root.topLevel
    x: root.railWidth / 2 - width / 2
    y: root.pad + Style.space(3)
    width: Style.space(10)
    height: width
    radius: width / 2
    // A deleted commit keeps its place as a hollow node, like a tombstone.
    color: root.row.deleted ? Color.background : root.lane
    border.width: root.row.deleted ? 2 : 0
    border.color: root.view.railColor
  }

  // Replies hang off a plain guide line, the way the site indents a thread.
  Rectangle {
    visible: !root.topLevel
    x: Style.space(4)
    width: 1
    height: root.height
    color: root.view.railColor
  }

  // --- The commit -------------------------------------------------------------

  Column {
    id: body
    x: root.railWidth
    y: root.topLevel ? root.pad : root.pad / 2
    width: root.width - root.railWidth - Style.space(12)
    spacing: Style.space(3)

    Item {
      width: body.width
      height: who.implicitHeight
      Mono {
        id: who
        width: parent.width - hash.implicitWidth - Style.space(8)
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: root.row.deleted ? root.view.dimmed("[deleted]")
          : "<b>" + root.view.esc(root.row.name) + "</b> "
            + root.view.dimmed(root.row.handle + " · " + root.age + (root.row.pending ? " · held" : ""))
      }
      Mono {
        id: hash
        anchors.right: parent.right
        text: root.row.hash
        color: Color.accent
        TapHandler { onTapped: root.view.openOnSite(root.row.url) }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
      }
    }

    Mono {
      width: body.width
      visible: text !== ""
      text: root.row.deleted ? "This commit was deleted." : root.row.body
      color: root.row.deleted ? root.view.dim : root.view.foreground
      font.pixelSize: Style.font.body
      wrapMode: Text.WrapAnywhere
    }

    Box {
      visible: !!root.row.quoted
      lines: 6
      text: root.row.quoted
        ? root.view.dimmed("❝ " + root.row.quoted.handle + " · " + Model.ageFor(root.row.quoted.created, root.view.now)
            + " · " + root.row.quoted.hash) + "<br>" + root.view.esc(root.row.quoted.body)
        : ""
      onTapped: root.view.openOnSite(root.row.quoted.url)
    }

    Box {
      visible: !!root.row.link
      lines: 3
      text: root.row.link ? root.view.dimmed("↗ " + root.row.link.site) + "<br>" + root.view.esc(root.row.link.title) : ""
      onTapped: root.view.openOnSite(root.row.link.url)
    }

    Action {
      visible: root.row.images > 0
      text: "[" + Model.plural(root.row.images, "image") + " · on the site]"
      onTapped: root.view.openOnSite(root.row.url)
    }

    // --- Actions: each one is also a key on the selected commit ---------------

    Row {
      visible: !root.row.deleted
      spacing: Style.space(14)

      Action {
        text: (root.row.starred ? "★" : "☆") + (root.row.stars > 0 ? " " + root.row.stars : "")
        color: root.row.starred ? Color.accent : root.view.dim
        onTapped: root.view.toggleStar(root.row.id)
      }
      Action {
        visible: root.topLevel
        text: "quote"
        onTapped: root.view.startQuote(root.commit)
      }
      Action {
        text: root.view.replyingTo === root.row.id ? "cancel" : "reply"
        onTapped: root.view.toggleReply(root.row.id)
      }
      Action {
        visible: root.row.replies > 0
        text: root.thread ? "▾ hide replies" : "▸ " + Model.plural(root.row.replies, "reply", "replies")
        color: Color.accent
        onTapped: root.view.toggleThread(root.row.id)
      }
      Action {
        text: "⧉"
        onTapped: root.view.copyLink(root.row)
      }
    }

    TextField {
      visible: root.view.replyingTo === root.row.id
      width: body.width
      placeholderText: "reply to " + root.row.handle + "…  (enter sends, esc cancels)"
      color: root.view.foreground
      font.family: root.view.fontFamily
      font.pixelSize: Style.font.body
      text: root.view.draftFor(root.row.id)
      onVisibleChanged: if (visible) forceActiveFocus()
      onTextEdited: root.view.keepDraft(root.row.id, text)
      onAccepted: root.view.sendReply(root.row.id, text)
      Keys.onEscapePressed: root.view.toggleReply(root.row.id)
    }

    // --- The thread: the open one in full, or the site's one-reply preview -----

    Repeater {
      model: root.thread ? root.thread.replies : (root.topLevel ? root.row.preview : [])
      Loader {
        required property var modelData
        width: body.width
        height: item ? item.implicitHeight : 0
        // Required properties are set at creation, so the source is set here.
        Component.onCompleted: setSource("LogRow.qml", {
          commit: modelData, view: root.view, depth: Math.min(root.depth + 1, 3), width: body.width
        })
        onWidthChanged: if (item) item.width = width
      }
    }

    Action {
      visible: !!root.thread && (root.thread.loading || root.thread.nextCursor !== "")
      text: root.thread && root.thread.loading ? "loading replies…" : "more replies…"
      onTapped: if (!root.thread.loading) root.view.loadMoreReplies(root.row.id, root.thread.nextCursor)
    }
  }

  // --- Building blocks ----------------------------------------------------------

  component Mono: Text {
    color: root.view.foreground
    font.family: root.view.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component Action: Mono {
    signal tapped()
    color: root.view.dim
    TapHandler { onTapped: parent.tapped() }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
  }

  component RailSegment: Rectangle {
    x: root.railWidth / 2 - 1
    width: 2
  }

  // A quoted commit or a link card: a bordered box, as on the site, without colour.
  component Box: Rectangle {
    id: box
    property alias text: boxText.text
    property int lines: 3
    signal tapped()
    width: body.width
    height: boxText.implicitHeight + Style.space(10)
    color: "transparent"
    border.width: 1
    border.color: root.view.railColor
    radius: Style.cornerRadius
    Mono {
      id: boxText
      x: Style.space(8)
      y: Style.space(5)
      width: box.width - Style.space(16)
      textFormat: Text.StyledText
      wrapMode: Text.WrapAnywhere
      maximumLineCount: box.lines
      elide: Text.ElideRight
    }
    TapHandler { onTapped: box.tapped() }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
  }
}

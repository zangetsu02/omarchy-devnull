import QtQuick
import QtQuick.Controls
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// One commit as `git log --graph` prints it, drawn the way a terminal would:
// the rail is characters in the author's lane, then the avatar in two cells,
// one header line — hash and handle left, age and counts anchored right — the
// body, and the actions.
// Replies are the same row one level in, closing the rail with ╰, and nest
// through a Loader of this same file.
//
// It only talks to `view` (FullPanel): the palette and every action go
// through it, so the row never reaches into the service behind it.
Item {
  id: root

  required property var commit
  required property var view
  property int depth: 0
  property bool selected: false
  // Set by the row above when this is the last reply in its thread: it decides
  // whether the rail closes with ╰ or carries on with ├.
  property bool lastReply: false
  // The last row in the list: its lane has nothing below to reach, so it stops
  // at the commit instead of trailing off into the gap under it.
  property bool last: false

  readonly property var row: Model.rowFor(commit)
  readonly property color lane: view.laneColor(row.lane)
  readonly property bool topLevel: depth === 0
  readonly property var thread: view.threadFor(row.id)
  readonly property real pad: topLevel ? Style.space(12) : Style.space(6)

  // The grid. Every column below is a whole number of these, so the rail, the
  // avatar and the text start on the same boundary on every line.
  Metrics { id: grid }
  readonly property real cell: grid.cell

  // The avatar IS the node: it sits on the lane, ringed in the author's colour,
  // the way dev-null draws its own graph. So the lane and the avatar share one
  // two-cell column, and a reply is that column indented, reached by an arm
  // drawn in the two cells before it.
  readonly property int gutterCells: 1
  readonly property int laneCol: gutterCells + depth * 2
  readonly property real textCol: grid.cell * (laneCol + 4)   // avatar(2) + its ring + a space

  implicitHeight: Math.max(body.implicitHeight, avatar.height) + pad * 2


  // The cursor, in its own column. Inset from the divider: welded to it, a
  // full-height bar in the action colour reads as a focus ring around the
  // pane rather than as a mark on one row.
  Rail {
    visible: root.selected
    x: Style.space(4)
    y: root.pad
    metrics: grid
    cells: 1
    headColor: root.view.primary
    tailColor: root.view.primary
    head: Model.GLYPHS.cursorBar
    tail: Model.GLYPHS.cursorBar
  }

  // --- The rail: drawn as a terminal would draw it ----------------------------

  Rail {
    x: grid.cell * root.laneCol
    y: root.pad
    rowHeight: root.height - root.pad - (root.last ? root.pad * 2 : 0)
    metrics: grid
    cells: 2
    headColor: root.lane
    tailColor: root.lane
    // Nothing: the avatar below covers this cell and marks the row itself.
    // A deleted commit has no avatar, so its tombstone shows through.
    head: root.row.deleted ? Model.nodeGlyph(root.commit, root.selected) : ""
  }

  // The arm reaching in from the lane this reply hangs off.
  Mono {
    visible: !root.topLevel
    x: grid.cell * (root.laneCol - 2)
    y: root.pad
    width: grid.cell * 2
    height: grid.cell * 2
    verticalAlignment: Text.AlignVCenter
    font.pixelSize: grid.size
    color: root.lane
    textFormat: Text.PlainText
    text: (root.lastReply ? Model.GLYPHS.lastBranch : Model.GLYPHS.branch) + Model.GLYPHS.dash
  }

  // --- The commit -------------------------------------------------------------

  Avatar {
    id: avatar
    // Centred on the lane, not on its column: the ring and its gap add four
    // pixels a side, which is exactly how far off centre it sat before.
    x: grid.cell * root.laneCol + grid.cell - implicitWidth / 2
    y: root.pad
    size: grid.cell * 2
    ring: root.lane
    source: root.row.deleted ? "" : root.row.avatar
    name: root.row.name
    clickable: !root.row.deleted
    onClicked: root.view.openProfile(root.row.username)
  }

  Column {
    id: body
    x: root.textCol
    y: root.pad
    width: root.width - x - Style.space(14)
    spacing: Style.space(4)

    // The header: hash and handle on the left, age and counts anchored right.
    // Nothing here is padded — QML anchors, and anchors cannot drift.
    Item {
      width: body.width
      height: hashLine.implicitHeight

      Mono {
        id: hashLine
        width: parent.width - counts.implicitWidth - grid.cell * 2
        font.pixelSize: grid.size
        color: root.selected ? Color.foreground : Color.muted
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.row.deleted ? "[deleted]" : Model.headerLeft(root.commit)
      }

      Mono {
        id: counts
        anchors.right: parent.right
        font.pixelSize: grid.size
        color: Color.muted
        textFormat: Text.PlainText
        text: root.row.deleted ? "" : Model.headerRight(root.commit, root.view.now)
      }
    }

    // Selectable, the way text in a terminal is. A drag here selects rather
    // than moving the cursor; a click anywhere else on the row still moves it.
    TextEdit {
      width: body.width
      visible: text !== ""
      readOnly: true
      selectByMouse: true
      persistentSelection: false
      text: root.row.deleted ? "This commit was deleted." : root.row.body
      color: root.row.deleted ? Color.muted : Color.foreground
      selectionColor: Qt.rgba(root.view.primary.r, root.view.primary.g, root.view.primary.b, 0.35)
      selectedTextColor: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.Wrap
    }

    Box {
      visible: !!root.row.quoted
      lines: 6
      heading: root.row.quoted
        ? "❝ " + root.row.quoted.name + "  " + root.row.quoted.handle + " · " + Model.ageFor(root.row.quoted.created, root.view.now)
        : ""
      text: root.row.quoted ? root.row.quoted.body : ""
      onTapped: root.view.openCommit(root.row.quoted.id)
    }

    Box {
      visible: !!root.row.link
      lines: 3
      image: root.row.link ? root.row.link.image : ""
      heading: root.row.link ? "↗ " + root.row.link.site : ""
      text: root.row.link ? root.row.link.title : ""
      onTapped: root.view.openOnSite(root.row.link.url)
    }

    CommitImages {
      width: body.width
      images: root.row.images
      view: root.view
      maxHeight: root.topLevel ? Style.space(340) : Style.space(220)
    }

    // --- Actions: each one is also a key on the selected commit ---------------

    Row {
      visible: !root.row.deleted
      spacing: Style.space(2)
      x: -Style.space(6)

      ActionButton {
        icon: root.row.starred ? Model.ICONS.star : Model.ICONS.unstarred
        label: root.row.stars > 0 ? String(root.row.stars) : ""
        active: root.row.starred
        activeColor: root.view.primary
        onClicked: root.view.toggleStar(root.row)
      }
      ActionButton {
        visible: root.topLevel
        icon: Model.ICONS.quote
        label: "quote"
        onClicked: root.view.startQuote(root.commit)
      }
      ActionButton {
        icon: Model.ICONS.reply
        label: root.view.replyingTo === root.row.id ? "cancel" : "reply"
        active: root.view.replyingTo === root.row.id
        onClicked: root.view.toggleReply(root.row.id)
      }
      ActionButton {
        visible: root.row.replies > 0
        icon: root.thread ? Model.ICONS.collapse : Model.ICONS.expand
        label: root.thread ? "hide replies" : Model.plural(root.row.replies, "reply", "replies")
        restColor: root.view.primary
        onClicked: root.view.toggleThread(root.row.id)
      }
      // A pastel comes out of a daily allowance, so the button goes quiet once
      // the day's are spent rather than offering one the server would refuse.
      ActionButton {
        visible: root.topLevel && root.view.pasteisLeft !== 0
        icon: Model.ICONS.pastel
        label: root.row.pasteis > 0 ? String(root.row.pasteis) : ""
        onClicked: root.view.givePastel(root.row.id)
      }
      ActionButton {
        icon: Model.ICONS.copy
        onClicked: root.view.copyLink(root.row)
      }
    }

    TextField {
      visible: root.view.replyingTo === root.row.id
      width: body.width
      placeholderText: "reply to " + root.row.handle + "…  (enter sends, esc cancels)"
      color: Color.foreground
      font.family: Style.font.family
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
        required property int index
        readonly property int siblings: root.thread ? root.thread.replies.length
                                                    : (root.topLevel ? root.row.preview.length : 0)
        Component.onCompleted: setSource("LogRow.qml", {
          commit: modelData, view: root.view, depth: Math.min(root.depth + 1, 3),
          width: body.width, lastReply: index === siblings - 1
        })
        onWidthChanged: if (item) item.width = width
      }
    }

    ActionButton {
      visible: !!root.thread && (root.thread.loading || root.thread.nextCursor !== "")
      label: root.thread && root.thread.loading ? "loading replies…" : "more replies…"
      onClicked: if (!root.thread.loading) root.view.loadMoreReplies(root.row.id, root.thread.nextCursor)
    }
  }

  // --- Building blocks ----------------------------------------------------------

  // A quoted commit or a link card: a bordered box, as on the site, with the
  // card's picture on the left when it has one.
  component Box: Rectangle {
    id: box
    property string heading
    property string text
    property string image: ""
    property int lines: 3
    signal tapped()
    readonly property real inset: Style.space(10)
    width: body.width
    height: Math.max(boxColumn.implicitHeight, thumb.visible ? thumb.height : 0) + inset * 1.4
    color: "transparent"
    border.width: 1
    border.color: root.view.railColor
    Picture {
      id: thumb
      visible: box.image !== ""
      x: box.inset * 0.7
      y: box.inset * 0.7
      width: Style.space(96)
      height: Style.space(54)
      radius: Style.space(4)
      source: box.image
    }
    Column {
      id: boxColumn
      x: thumb.visible ? thumb.x + thumb.width + box.inset : box.inset
      y: box.inset * 0.7
      width: box.width - x - box.inset
      spacing: Style.space(2)
      Mono { width: parent.width; text: box.heading; color: Color.muted; elide: Text.ElideRight }
      Mono {
        width: parent.width
        text: box.text
        wrapMode: Text.Wrap
        maximumLineCount: box.lines
        elide: Text.ElideRight
      }
    }
    HoverHandler { id: boxHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: box.tapped() }
  }
}

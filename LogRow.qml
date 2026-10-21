import QtQuick
import QtQuick.Controls
import qs.Commons
import "Model.js" as Model

// One commit as `git log --graph` would print it: a rail in the author's lane,
// the avatar, who and when, the body, and a row of actions. Replies use the
// same row one level in, behind a guide line instead of the rail, and nest
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
  // The lane of the commit drawn above, for the rail segment over the node.
  property color laneAbove: view.railColor

  readonly property var row: Model.rowFor(commit)
  readonly property color lane: view.laneColor(row.lane)
  readonly property bool topLevel: depth === 0
  readonly property var thread: view.threadFor(row.id)
  readonly property real railWidth: topLevel ? Style.space(34) : Style.space(18)
  readonly property real avatarSize: topLevel ? Style.space(34) : Style.space(24)
  readonly property real pad: topLevel ? Style.space(12) : Style.space(6)
  readonly property real gutter: Style.space(10)

  implicitHeight: Math.max(body.implicitHeight, avatar.height) + pad * 2

  // Selected: a wash and a bar in the action blue, the way the site marks focus.
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: root.railWidth
    visible: root.selected
    color: Qt.rgba(root.view.primary.r, root.view.primary.g, root.view.primary.b, 0.07)
    Rectangle { width: 2; height: parent.height; color: root.view.primary }
  }

  // --- The rail ---------------------------------------------------------------

  RailSegment { visible: root.topLevel; height: node.y; color: root.laneAbove }
  RailSegment { visible: root.topLevel; y: node.y + node.height; height: root.height - y; color: root.lane }

  Rectangle {
    id: node
    visible: root.topLevel
    x: root.railWidth / 2 - width / 2
    y: root.pad + root.avatarSize / 2 - height / 2
    width: Style.space(12)
    height: width
    radius: width / 2
    // A deleted commit keeps its place as a hollow node, like a tombstone.
    color: root.row.deleted ? Color.background : root.lane
    border.width: 2
    border.color: root.row.deleted ? root.view.railColor : Color.background
  }

  // Replies hang off a plain guide line, the way the site indents a thread.
  Rectangle {
    visible: !root.topLevel
    x: Style.space(6)
    width: 1
    height: root.height
    color: root.view.railColor
  }

  // Rows are split by a hairline that starts after the rail, so the graph runs on.
  Rectangle {
    visible: root.topLevel
    anchors.bottom: parent.bottom
    x: root.railWidth
    width: root.width - x
    height: 1
    color: root.view.railColor
  }

  // --- The commit -------------------------------------------------------------

  Avatar {
    id: avatar
    x: root.railWidth + Style.space(4)
    y: root.pad
    size: root.avatarSize
    source: root.row.deleted ? "" : root.row.avatar
    name: root.row.name
    TapHandler { onTapped: root.view.openProfile(root.row.username) }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
  }

  Column {
    id: body
    x: avatar.x + avatar.width + root.gutter
    y: root.pad
    width: root.width - x - Style.space(14)
    spacing: Style.space(4)

    Item {
      width: body.width
      height: who.implicitHeight
      Row {
        id: who
        spacing: Style.space(6)
        width: parent.width - hash.implicitWidth - Style.space(8)
        Mono {
          id: nameText
          text: root.row.deleted ? "[deleted]" : root.row.name
          color: root.row.deleted ? Color.muted : Color.foreground
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          TapHandler { onTapped: root.view.openProfile(root.row.username) }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        Mono {
          visible: !root.row.deleted
          anchors.baseline: nameText.baseline
          text: root.row.handle + " · " + Model.ageFor(root.row.created, root.view.now) + (root.row.pending ? " · held" : "")
          color: Color.muted
          elide: Text.ElideRight
        }
      }
      Mono {
        id: hash
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.row.hash
        color: hashHover.hovered ? root.view.primary : Color.muted
        TapHandler { onTapped: root.view.openOnSite(root.row.url) }
        HoverHandler { id: hashHover; cursorShape: Qt.PointingHandCursor }
      }
    }

    Mono {
      width: body.width
      visible: text !== ""
      text: root.row.deleted ? "This commit was deleted." : root.row.body
      color: root.row.deleted ? Color.muted : Color.foreground
      font.pixelSize: Style.font.body
      lineHeight: 1.3
      wrapMode: Text.WrapAnywhere
    }

    Box {
      visible: !!root.row.quoted
      lines: 6
      heading: root.row.quoted
        ? "❝ " + root.row.quoted.name + "  " + root.row.quoted.handle + " · " + Model.ageFor(root.row.quoted.created, root.view.now)
        : ""
      text: root.row.quoted ? root.row.quoted.body : ""
      onTapped: root.view.openOnSite(root.row.quoted.url)
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
        Component.onCompleted: setSource("LogRow.qml", {
          commit: modelData, view: root.view, depth: Math.min(root.depth + 1, 3), width: body.width
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

  component RailSegment: Rectangle {
    x: root.railWidth / 2 - 1
    width: 2
  }

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
    color: boxHover.hovered ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04) : "transparent"
    border.width: 1
    border.color: root.view.railColor
    radius: Style.space(6)
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
        wrapMode: Text.WrapAnywhere
        maximumLineCount: box.lines
        elide: Text.ElideRight
      }
    }
    HoverHandler { id: boxHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: box.tapped() }
  }
}

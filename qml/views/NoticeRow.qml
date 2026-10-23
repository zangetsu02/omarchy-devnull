import QtQuick
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// One notification as a row on a grey rail: a hollow node holding the type's
// icon, who did it (up to three avatars), what they did, and the words —
// theirs as a body, yours as a muted box.
Item {
  id: root

  required property var notification
  required property var view

  readonly property var notice: Model.noticeFor(notification)
  readonly property var actors: (notification.actors && notification.actors.length ? notification.actors : [notice.actor]).slice(0, 3)
  readonly property color tint: view.noticeColor(notice.type)
  readonly property real railWidth: Style.space(50)
  readonly property real pad: Style.space(12)

  implicitHeight: body.implicitHeight + pad * 2

  // A click anywhere else on the row does the notice's natural thing. It sits
  // under everything, and the MouseAreas above take their own clicks first.
  Clickable { id: rowArea; anchors.fill: parent; onClicked: root.openTarget() }

  function openTarget() {
    var target = Model.noticeTarget(root.notice, root.view.myUsername)
    if (target) root.view.goTo(target.page, target.argument)
  }

  Metrics { id: grid }

  // The same rail the log draws, so the two pages read as one program. An
  // unread notice is the filled node; a read one is hollow.
  Rail {
    x: root.railWidth / 2 - grid.cell
    y: root.pad
    metrics: grid
    headColor: root.notice.unread ? root.tint : root.view.railColor
    tailColor: root.view.railColor
    head: root.notice.unread ? Model.GLYPHS.nodeHere : Model.GLYPHS.node
  }

  Column {
    id: body
    x: root.railWidth + Style.space(6)
    y: root.pad
    width: root.width - x - Style.space(14)
    spacing: Style.space(5)

    Item {
      width: body.width
      height: faces.height
      Row {
        id: faces
        spacing: -Style.space(6)
        Repeater {
          model: root.actors
          Avatar {
            required property var modelData
            size: Style.space(26)
            source: modelData.avatar_url || ""
            name: modelData.name || modelData.username || ""
            clickable: true
            onClicked: root.view.openProfile(modelData.username)
          }
        }
      }
      Mono {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Model.ageFor(root.notice.created, root.view.now)
        color: Color.muted
      }
    }

    // Who did it is its own link to their profile; the rest of the sentence is not.
    Flow {
      width: body.width
      spacing: Style.space(6)
      Mono {
        visible: root.notice.aboutYou
        text: "You"
        font.pixelSize: Style.font.body
        font.bold: true
      }
      LinkText {
        visible: !root.notice.aboutYou
        text: root.notice.actor.name || root.notice.actor.username || "?"
        font.pixelSize: Style.font.body
        font.bold: true
        onClicked: root.view.openProfile(root.notice.actor.username)
      }
      Mono {
        visible: !root.notice.aboutYou
        text: root.notice.others > 0 ? "and " + Model.plural(root.notice.others, "other") : "@" + (root.notice.actor.username || "?")
        color: Color.muted
        font.pixelSize: Style.font.body
      }
      // The icon used to be the node; the node is the unread mark now, so the
      // kind of notification says itself here instead.
      Mono { text: root.notice.icon; color: root.tint; font.pixelSize: Style.font.body }
      Mono { text: root.notice.verb; font.pixelSize: Style.font.body }
    }

    // Their words, as a block that lights up: it opens the commit they are in.
    Rectangle {
      visible: root.notice.theirs && root.notice.body !== ""
      width: body.width
      height: theirs.implicitHeight + Style.space(8)
      x: -Style.space(6)
      color: "transparent"
      Mono {
        id: theirs
        x: Style.space(6)
        y: Style.space(4)
        width: parent.width - Style.space(12)
        text: root.notice.body
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
      }
      Clickable { id: theirsArea; anchors.fill: parent; onClicked: root.view.openCommit(root.notice.commitId) }
    }

    Rectangle {
      visible: !root.notice.theirs && root.notice.body !== ""
      width: body.width
      height: own.implicitHeight + Style.space(12)
      color: "transparent"
      border.width: 1
      border.color: root.view.railColor
      Mono {
        id: own
        x: Style.space(10)
        y: Style.space(6)
        width: parent.width - Style.space(20)
        text: root.notice.body
        color: Color.muted
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
      Clickable { id: ownArea; anchors.fill: parent; onClicked: root.view.openCommit(root.notice.commitId) }
    }

    Mono {
      visible: root.notice.reason !== ""
      width: body.width
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      text: root.view.dimmed("reason: ") + root.view.esc(root.notice.reason)
    }
  }

  // A MouseArea, not a TapHandler: it keeps the click, so a name inside the row
  // opens the profile without the row behind it also opening the commit.
  component Clickable: MouseArea {
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
  }
}

import QtQuick
import qs.Commons
import "Model.js" as Model

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

  // The whole row lights up: it is one click away from where it leads.
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: root.railWidth
    visible: rowArea.containsMouse
    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
  }

  function openTarget() {
    var target = Model.noticeTarget(root.notice, root.view.myUsername)
    if (target) root.view.goTo(target.page, target.argument)
  }

  Rectangle {
    x: root.railWidth / 2 - 1
    width: 2
    height: root.height
    color: root.view.railColor
  }

  Rectangle {
    x: root.railWidth / 2 - width / 2
    y: root.pad
    width: Style.space(30)
    height: width
    radius: width / 2
    color: Color.background
    // Unread on this visit: the node rings in the action blue, as on the site.
    border.width: 2
    border.color: root.notice.unread ? root.view.primary : root.view.railColor
    Mono {
      anchors.centerIn: parent
      text: root.notice.icon
      color: root.tint
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    x: root.railWidth
    width: root.width - x
    height: 1
    color: root.view.railColor
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
      Mono { text: root.notice.verb; font.pixelSize: Style.font.body }
    }

    // Their words, as a block that lights up: it opens the commit they are in.
    Rectangle {
      visible: root.notice.theirs && root.notice.body !== ""
      width: body.width
      height: theirs.implicitHeight + Style.space(8)
      x: -Style.space(6)
      radius: Style.space(6)
      color: theirsArea.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
      Mono {
        id: theirs
        x: Style.space(6)
        y: Style.space(4)
        width: parent.width - Style.space(12)
        text: root.notice.body
        font.pixelSize: Style.font.body
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
      }
      Clickable { id: theirsArea; anchors.fill: parent; onClicked: root.view.openCommit(root.notice.commitId) }
    }

    Rectangle {
      visible: !root.notice.theirs && root.notice.body !== ""
      width: body.width
      height: own.implicitHeight + Style.space(12)
      color: ownArea.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : "transparent"
      border.width: 1
      border.color: ownArea.containsMouse ? Color.muted : root.view.railColor
      radius: Style.space(6)
      Mono {
        id: own
        x: Style.space(10)
        y: Style.space(6)
        width: parent.width - Style.space(20)
        text: root.notice.body
        color: Color.muted
        wrapMode: Text.WrapAnywhere
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

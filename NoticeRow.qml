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
            TapHandler { onTapped: root.view.openProfile(modelData.username) }
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

    Mono {
      width: body.width
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      font.pixelSize: Style.font.body
      text: "<b>" + root.view.esc(root.notice.actor.name || root.notice.actor.username) + "</b> "
        + root.view.dimmed(root.notice.others > 0 ? "and " + Model.plural(root.notice.others, "other") : "@" + (root.notice.actor.username || "?"))
        + " " + root.view.esc(root.notice.verb)
    }

    Mono {
      visible: root.notice.theirs && root.notice.body !== ""
      width: body.width
      text: root.notice.body
      font.pixelSize: Style.font.body
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 4
      elide: Text.ElideRight
    }

    Rectangle {
      visible: !root.notice.theirs && root.notice.body !== ""
      width: body.width
      height: own.implicitHeight + Style.space(12)
      color: "transparent"
      border.width: 1
      border.color: root.view.railColor
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
    }

    Mono {
      visible: root.notice.reason !== ""
      width: body.width
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      text: root.view.dimmed("reason: ") + root.view.esc(root.notice.reason)
    }
  }

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler {
    onTapped: root.notice.type === "followed"
      ? root.view.openProfile(root.notice.actor.username)
      : root.view.openOnSite(root.notice.url)
  }
}

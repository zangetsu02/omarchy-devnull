import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "zangetsu.devnull"
  ipcTarget: "devnull"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color cardFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property color cardLine: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  readonly property int bodyLines: setting("bodyLines", 2)
  readonly property var badge: Model.badgeFor(feed.unreadCount, feed.broken)

  // Which commit has its reply field open. Kept as an id, not an index: the
  // feed is replaced wholesale on every refresh.
  property string replyingTo: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: feed
    settings: root.settings
    panelOpen: root.opened
  }

  onOpenedChanged: {
    if (opened) feed.openPanel()
    else {
      feed.closePanel()
      root.replyingTo = ""
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    iconComponent: Component {
      Item {
        DevNullIcon {
          id: glyph
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: feed.broken ? root.urgent : root.barForeground
          filled: root.badge.state === "unread"
          crossed: feed.broken
        }

        Text {
          visible: root.badge.text !== "" && root.badge.state === "unread"
          text: root.badge.text
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.space(8)
          anchors.left: glyph.right
          anchors.verticalCenter: glyph.verticalCenter
          anchors.leftMargin: Style.space(2)
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.MiddleButton) feed.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function (t) { if (t === "r" || t === "R") feed.refresh() }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // --- What happened to you -----------------------------------------

        Text {
          visible: feed.notifications.length > 0
          text: "What happened to you"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
        }

        Repeater {
          model: feed.notifications
          Rectangle {
            width: column.width
            height: line.implicitHeight + Style.space(12)
            radius: Style.space(6)
            color: root.cardFill
            border.color: root.cardLine
            border.width: 1

            Text {
              id: line
              anchors.fill: parent
              anchors.margins: Style.space(6)
              text: Model.clampBody(Model.summaryFor(modelData), root.bodyLines, 52)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              wrapMode: Text.NoWrap
            }
          }
        }

        // --- The feed -------------------------------------------------------

        Text {
          text: "Latest"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
        }

        Repeater {
          model: feed.commits
          Rectangle {
            id: card
            readonly property var row: Model.rowFor(modelData)
            width: column.width
            height: body.y + body.implicitHeight + reply.height + Style.space(10)
            radius: Style.space(6)
            color: root.cardFill
            border.color: root.cardLine
            border.width: 1

            Text {
              id: heading
              x: Style.space(6)
              y: Style.space(5)
              text: card.row.hash + "  " + card.row.handle + (card.row.pending ? "  (held)" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(9)
            }

            Text {
              id: body
              x: Style.space(6)
              y: heading.y + heading.implicitHeight + Style.space(3)
              width: parent.width - Style.space(60)
              text: Model.clampBody(card.row.body, root.bodyLines, 48)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              wrapMode: Text.NoWrap

              MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["xdg-open", card.row.url])
              }
            }

            // Star: the count sits next to it so the tap has something to move.
            Text {
              id: star
              text: (card.row.starred ? "★ " : "☆ ") + card.row.stars
              color: card.row.starred ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              y: heading.y

              MouseArea {
                anchors.fill: parent
                onClicked: feed.toggleStar(card.row.id)
              }
            }

            Text {
              text: "reply"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(9)
              anchors.right: star.right
              y: star.y + star.implicitHeight + Style.space(4)

              MouseArea {
                anchors.fill: parent
                onClicked: root.replyingTo = (root.replyingTo === card.row.id ? "" : card.row.id)
              }
            }

            Item {
              id: reply
              width: parent.width
              height: root.replyingTo === card.row.id ? field.implicitHeight + Style.space(8) : 0
              visible: height > 0
              y: body.y + body.implicitHeight + Style.space(4)

              TextField {
                id: field
                width: parent.width - Style.space(12)
                x: Style.space(6)
                placeholderText: "reply as you would on the site"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                onAccepted: {
                  feed.sendReply(card.row.id, text)
                  text = ""
                  root.replyingTo = ""
                }
              }
            }
          }
        }

        Text {
          visible: feed.nextCursor !== ""
          text: "older…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
          MouseArea { anchors.fill: parent; onClicked: feed.loadMore() }
        }

        // --- What went wrong -------------------------------------------------

        Text {
          visible: feed.replyStatus !== ""
          text: feed.replyStatus
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
          width: column.width
          wrapMode: Text.WordWrap
        }

        Text {
          visible: feed.lastError !== ""
          text: feed.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
          width: column.width
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

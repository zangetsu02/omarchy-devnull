import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar icon and its popup: who reached you and the last few commits, at a
// glance. Starring, replying and scrolling back live in the full view (Open).
Panel {
  id: root
  moduleName: "zangetsu.devnull"
  ipcTarget: "devnull"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int bodyLines: setting("bodyLines", 2)
  readonly property var badge: Model.badgeFor(feed.unreadCount, feed.broken)
  // How many of each the popup shows; the rest is one click away in Open.
  readonly property int shownNotifications: 3
  readonly property int shownCommits: 3

  property double now: Date.now()
  Timer { interval: 60000; repeat: true; running: root.opened; onTriggered: root.now = Date.now() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: feed
    settings: root.settings
    panelOpen: root.opened
  }

  onOpenedChanged: {
    if (opened) {
      root.now = Date.now()
      feed.openPanel()
    } else feed.closePanel()
  }

  // Same dance as the Spotify full player: hide first, summon on the next
  // turn, so Wayland unmaps the old surface before the shell maps it again.
  function openFull(commitId) {
    root.close()
    if (!bar || !bar.shell) return
    var payload = JSON.stringify({ commit: commitId || "" })
    bar.shell.hide("zangetsu.devnull")
    Qt.callLater(function () {
      if (root.bar && root.bar.shell) root.bar.shell.summon("zangetsu.devnull", payload)
    })
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
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function (t) {
        if (t === "r" || t === "R") feed.refresh()
        else if (t === "o" || t === "O") root.openFull("")
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: column.width
          height: title.implicitHeight
          Text {
            id: title
            text: "/dev/null"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            anchors.right: parent.right
            anchors.baseline: title.baseline
            text: feed.username !== "" ? "@" + feed.username : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // --- Who reached you --------------------------------------------------

        Text {
          visible: feed.notifications.length > 0
          text: "FOR YOU"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          topPadding: Style.space(4)
        }

        Repeater {
          model: feed.notifications.slice(0, root.shownNotifications)
          Text {
            width: column.width
            text: Model.summaryFor(modelData)
            color: modelData.read_at ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        // --- The last few commits ---------------------------------------------

        Text {
          text: "LATEST"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          topPadding: Style.space(4)
        }

        Repeater {
          model: feed.commits.slice(0, root.shownCommits)
          CommitCard {
            required property var modelData
            width: column.width
            row: Model.rowFor(modelData)
            bodyLines: root.bodyLines
            fontFamily: root.fontFamily
            foreground: root.foreground
            dim: root.dim
            now: root.now
            onClicked: root.openFull(row.id)
          }
        }

        Text {
          visible: feed.lastError !== ""
          text: feed.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          width: column.width
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: column.width; foreground: root.foreground }

        Item {
          width: column.width
          height: openButton.implicitHeight
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: feed.updatedAt !== "" ? "updated " + Model.ageFor(feed.updatedAt, root.now) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            id: openButton
            anchors.right: parent.right
            text: "Open"
            iconText: "↗"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            tooltipText: "Open the full view (o)"
            onClicked: root.openFull("")
          }
        }
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar icon and its popup: a glance at who reached you and the last few
// commits, drawn like the full client. Every row opens the full client on
// its page; starring, replying and scrolling back live there.
Panel {
  id: root
  moduleName: "zangetsu.devnull"
  ipcTarget: "devnull"
  manageIpc: false

  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property var scheme: Model.paletteFor(Color.background.hslLightness)
  readonly property color railColor: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)

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
  function openFull(page, argument) {
    root.close()
    if (!bar || !bar.shell) return
    var payload = JSON.stringify({ page: page || "", argument: argument || "" })
    bar.shell.hide(root.moduleName)
    Qt.callLater(function () {
      if (root.bar && root.bar.shell) root.bar.shell.summon(root.moduleName, payload)
    })
  }

  // "<b>Tom</b> replied  Right back at you…", escaped for StyledText.
  function sentence(notice) {
    var who = notice.aboutYou ? "You" : (notice.actor.name || notice.actor.username || "?")
    return "<b>" + esc(who) + "</b> " + esc(notice.verb)
      + (notice.body ? "  " + muted(notice.body) : "")
  }
  function esc(text) { return Model.escapeHtml(text) }
  function muted(text) { return Model.colored(text, Color.muted) }

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

        Mono {
          visible: root.badge.text !== "" && root.badge.state === "unread"
          text: root.badge.text
          color: root.urgent
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
        else if (t === "o" || t === "O") root.openFull("", "")
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(4)

        // --- Header: the wordmark, and you ----------------------------------------

        Item {
          width: column.width
          height: Math.max(mark.implicitHeight, me.implicitHeight)
          Row {
            id: mark
            anchors.verticalCenter: parent.verticalCenter
            Mono { text: "/dev"; font.pixelSize: Style.font.subtitle + 2; font.bold: true }
            Mono { text: "/"; color: root.scheme.lanes[0]; font.pixelSize: Style.font.subtitle + 2; font.bold: true }
            Mono { text: "null"; font.pixelSize: Style.font.subtitle + 2; font.bold: true }
          }
          Row {
            id: me
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Mono { anchors.verticalCenter: parent.verticalCenter; text: feed.username !== "" ? "@" + feed.username : ""; color: Color.muted }
            Avatar {
              size: Style.space(22)
              ring: root.scheme.lanes[Model.laneOf({ author: feed.me })]
              source: feed.me.avatar_url || ""
              name: feed.me.name || feed.username
              clickable: true
              onClicked: root.openFull("profile", feed.username)
            }
          }
        }

        // --- Who reached you --------------------------------------------------------

        SectionLabel { visible: feed.notifications.length > 0; text: "FOR YOU" }

        Repeater {
          model: feed.notifications.slice(0, root.shownNotifications)
          GlanceNotice {}
        }

        // --- The last few commits ---------------------------------------------------

        SectionLabel { text: "LATEST" }

        Repeater {
          model: feed.commits.slice(0, root.shownCommits)
          GlanceCommit {}
        }

        Mono {
          visible: feed.lastError !== ""
          width: column.width
          text: feed.lastError
          color: root.urgent
          wrapMode: Text.WordWrap
        }

        // --- Footer -------------------------------------------------------------------

        Rectangle { width: column.width; height: 1; color: root.railColor }

        Item {
          width: column.width
          height: openButton.height + Style.space(6)
          Mono {
            anchors.verticalCenter: parent.verticalCenter
            text: feed.updatedAt !== "" ? "updated " + Model.ageFor(feed.updatedAt, root.now) : ""
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            id: openButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: openLabel.implicitWidth + Style.space(24)
            height: openLabel.implicitHeight + Style.space(10)
            radius: Style.space(6)
            color: openArea.containsMouse ? Qt.lighter(root.scheme.primary, 1.12) : root.scheme.primary
            Mono {
              id: openLabel
              anchors.centerIn: parent
              text: "Open   o"
              color: Color.background
              font.bold: true
            }
            MouseArea {
              id: openArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openFull("", "")
            }
          }
        }
      }
    }
  }

  // --- Building blocks ------------------------------------------------------------

  component SectionLabel: Mono {
    topPadding: Style.space(10)
    bottomPadding: Style.space(2)
    color: Color.muted
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  // A row that lights up and opens the full client somewhere when clicked.
  component GlanceArea: Rectangle {
    id: area
    signal clicked()
    width: column.width
    radius: Style.space(6)
    color: hover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06) : "transparent"
    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: area.clicked()
    }
  }

  // One notification on one line: its icon in its colour, who, what, the words.
  component GlanceNotice: GlanceArea {
    id: glance
    required property var modelData
    readonly property var notice: Model.noticeFor(modelData)
    height: Style.space(32)
    onClicked: {
      var target = Model.noticeTarget(glance.notice, feed.username)
      root.openFull(target ? target.page : "notifications", target ? target.argument : "")
    }

    Row {
      x: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(12)
      spacing: Style.space(8)

      Mono {
        width: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: glance.notice.icon
        color: Model.noticeTint(glance.notice.type, root.scheme) || Color.muted
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Avatar {
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(20)
        source: glance.notice.actor.avatar_url || ""
        name: glance.notice.actor.name || glance.notice.actor.username || ""
      }
      Mono {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(60) - age.implicitWidth
        elide: Text.ElideRight
        textFormat: Text.StyledText
        color: glance.notice.unread ? Color.foreground : Color.muted
        text: root.sentence(glance.notice)
      }
      Mono {
        id: age
        anchors.verticalCenter: parent.verticalCenter
        text: Model.ageFor(glance.notice.created, root.now)
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }
  }

  // One commit on the lane rail: avatar, who and when, a couple of lines, the counts.
  component GlanceCommit: GlanceArea {
    id: glance
    required property var modelData
    readonly property var row: Model.rowFor(modelData)
    readonly property color lane: root.scheme.lanes[row.lane]
    readonly property real railWidth: Style.space(22)
    height: content.implicitHeight + Style.space(16)
    onClicked: root.openFull("commit", glance.row.id)

    // The rail runs through every row in each author's lane, like the log.
    Rectangle {
      x: glance.railWidth / 2 - 1
      width: 2
      height: parent.height
      color: glance.lane
      opacity: 0.7
    }
    Rectangle {
      x: glance.railWidth / 2 - width / 2
      y: Style.space(14)
      width: Style.space(10)
      height: width
      radius: width / 2
      color: glance.lane
      border.width: 2
      border.color: Color.background
    }

    Avatar {
      id: face
      x: glance.railWidth + Style.space(4)
      y: Style.space(8)
      size: Style.space(26)
      source: glance.row.avatar
      name: glance.row.name
    }

    Column {
      id: content
      x: face.x + face.width + Style.space(10)
      y: Style.space(8)
      width: glance.width - x - Style.space(8)
      spacing: Style.space(3)

      Item {
        width: content.width
        height: who.implicitHeight
        Mono {
          id: who
          width: parent.width - hash.implicitWidth - Style.space(8)
          elide: Text.ElideRight
          textFormat: Text.StyledText
          text: "<b>" + root.esc(glance.row.name) + "</b>  "
            + root.muted(glance.row.handle + " · " + Model.ageFor(glance.row.created, root.now))
        }
        Mono {
          id: hash
          anchors.right: parent.right
          text: glance.row.hash
          color: Color.muted
        }
      }
      Mono {
        width: content.width
        visible: text !== ""
        text: glance.row.body
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: root.bodyLines
        elide: Text.ElideRight
      }
      Mono {
        visible: glance.row.images.length > 0 || !!glance.row.link
        width: content.width
        elide: Text.ElideRight
        text: glance.row.images.length > 0
          ? "▣ " + Model.plural(glance.row.images.length, "picture")
          : "↗ " + (glance.row.link ? glance.row.link.site + " · " + glance.row.link.title : "")
        color: Color.muted
      }
      Row {
        spacing: Style.space(14)
        Mono {
          text: (glance.row.starred ? Model.ICONS.star : Model.ICONS.unstarred) + " " + glance.row.stars
          color: glance.row.starred ? root.scheme.primary : Color.muted
        }
        Mono { text: Model.ICONS.reply + " " + glance.row.replies; color: Color.muted }
      }
    }
  }
}

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import "Model.js" as Model

// The full view behind Open: dev-null in the shell, drawn like a terminal.
// Sections on the left (Log, Notifications, Starred, Profile), the page in the
// middle, who you are and the keys on the right, a status line at the bottom.
// Background, text and font are the Omarchy theme's; the author lanes and the
// action blue are dev-null's own.
//
// Every row and page talks only to this file; it is the one that knows the
// service. The shell mounts it only while it is summoned, so polling stops
// when it is closed.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "zangetsu.devnull"

  // --- Look ---------------------------------------------------------------------

  readonly property var scheme: Model.paletteFor(Color.background.hslLightness)
  readonly property color primary: scheme.primary
  readonly property color destructive: scheme.destructive
  readonly property color railColor: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
  property double now: Date.now()

  function laneColor(index) { return scheme.lanes[index] || scheme.lanes[0] }
  function esc(text) {
    return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
  function dimmed(text) { return "<font color='" + Color.muted + "'>" + esc(text) + "</font>" }

  function noticeColor(type) { return Model.noticeTint(type, scheme) || Color.muted }

  // --- State --------------------------------------------------------------------

  // "log", "notifications", "starred" or "profile".
  property string page: "log"
  property string profileName: ""
  property var history: []
  property string replyingTo: ""
  // Per commit id, not per row: the feed is replaced on every refresh.
  property var drafts: ({})
  property string composerText: ""
  property var quoting: null
  property string status: ""
  property bool statusFailed: false
  property bool awaitingG: false
  property var composerField: null

  readonly property var me: feed.me
  readonly property string myUsername: feed.me.username || feed.username
  readonly property int unread: feed.notifications.filter(function (n) { return !n.read_at }).length
  // The list the keys act on, on the page in front.
  readonly property var activeList: page === "log" ? logList
    : page === "starred" ? starredList
    : page === "profile" && profilePage.tab === "commits" ? profilePage.commitList
    : null
  readonly property var selectedCommit: activeList ? activeList.selectedCommit : null

  Timer { interval: 60000; repeat: true; running: root.opened; onTriggered: root.now = Date.now() }
  Timer { id: statusClear; interval: 6000; onTriggered: root.status = "" }

  Service {
    id: feed
    settings: ({})
    panelOpen: root.opened
    onReplyDone: function (id, answer) {
      if (Model.keepsDraft(answer)) return
      root.drafts = Model.clearDraft(root.drafts, id)
      if (root.replyingTo === id) root.replyingTo = ""
    }
    onTold: function (text, failed) { root.say(text, failed) }
    onCommitDone: function (answer) {
      if (answer.error) return
      root.composerText = ""
      root.quoting = null
    }
  }

  Pager { id: starred; service: feed }

  // --- What rows and pages call ---------------------------------------------------

  function threadFor(id) { return feed.threads[id] || null }
  function toggleStar(row) { feed.toggleStar(row.id, row.starred) }
  function toggleThread(id) { feed.toggleThread(id) }
  function loadMoreReplies(id, cursor) { feed.loadThread(id, cursor) }
  function draftFor(id) { return Model.draftFor(drafts, id) }
  function keepDraft(id, text) { drafts = Model.withDraft(drafts, id, text) }
  // The draft is cleared only once the reply lands: if the server refuses it,
  // what was typed is the only copy.
  function sendReply(id, text) { if (text.trim() !== "") feed.sendReply(id, text) }
  function toggleReply(id) {
    replyingTo = replyingTo === id ? "" : id
    if (replyingTo === "") scope.forceActiveFocus()
  }
  function startQuote(commit) {
    quoting = commit
    goTo("log", "")
    focusComposer()
  }
  function focusComposer() { if (composerField) composerField.forceActiveFocus() }
  function leaveComposer() {
    quoting = null
    scope.forceActiveFocus()
  }
  function postComposer() {
    if (composerText.trim() === "" || Model.charsLeft(composerText) < 0) return
    feed.postCommit(composerText, quoting ? quoting.id : "")
  }
  function openOnSite(url) {
    var safe = Model.webUrl(url)
    if (safe) Quickshell.execDetached(["xdg-open", safe])
  }
  function copyLink(row) {
    Quickshell.execDetached(["wl-copy", row.url])
    say("Copied link to " + row.hash, false)
  }
  function openProfile(username) { if (username) goTo("profile", username) }
  function showImages(images, index) { viewer.show(images, index) }
  function say(text, failed) {
    status = text
    statusFailed = failed
    if (text) statusClear.restart()
  }

  // --- Navigation: a page, and the way back ----------------------------------------

  function goTo(name, username) {
    if (name === page && (name !== "profile" || username === profileName)) return
    history = history.concat([{ page: page, username: profileName }])
    show(name, username)
  }
  function back() {
    if (history.length === 0) return
    var last = history[history.length - 1]
    history = history.slice(0, -1)
    show(last.page, last.username)
  }
  function show(name, username) {
    page = name
    if (name === "profile") profileName = username || myUsername
    if (name === "starred") starred.args = ["starred"]
    replyingTo = ""
    scope.forceActiveFocus()
  }

  // --- Host --------------------------------------------------------------------

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (shell && shell.bar && typeof shell.bar.hideBarWidget === "function")
      shell.bar.hideBarWidget(pluginId)
    history = []
    show("log", "")
    logList.selectedId = String(payload.commit || "")
    now = Date.now()
    opened = true
    feed.openPanel()
    feed.dispatch("me")
    Qt.callLater(function () { scope.forceActiveFocus() })
  }

  function close() {
    viewer.close()
    opened = false
    replyingTo = ""
    feed.closePanel()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // --- Keys ---------------------------------------------------------------------

  // Keys on the selected commit, wherever the commit list is.
  readonly property var commitKeys: ({
    "j": function (list) { list.move(1) },
    "k": function (list) { list.move(-1) },
    "s": function (list, c) { root.toggleStar(Model.rowFor(c)) },
    "r": function (list, c) { root.toggleReply(c.id) },
    "q": function (list, c) { root.startQuote(c) },
    "o": function (list, c) { root.toggleThread(c.id) },
    "y": function (list, c) { root.copyLink(Model.rowFor(c)) },
    "p": function (list, c) { root.openProfile(Model.rowFor(c).username) },
    "\r": function (list, c) { root.openOnSite(c.html_url) }
  })
  readonly property var pageKeys: ({
    "1": function () { root.goTo("log", ""); feed.switchLog("following") },
    "2": function () { root.goTo("log", ""); feed.switchLog("latest") },
    "3": function () { root.goTo("log", ""); feed.switchLog("trending") },
    "c": function () { root.goTo("log", ""); root.focusComposer() },
    "R": function () { feed.refresh() }
  })
  // `g` then a letter goes somewhere, as on the site.
  readonly property var goKeys: ({
    "l": function () { root.goTo("log", "") },
    "n": function () { root.goTo("notifications", "") },
    "s": function () { root.goTo("starred", "") },
    "p": function () { root.goTo("profile", root.myUsername) }
  })

  function handleKey(event) {
    if (viewer.handleKey(event)) return true
    if (event.key === Qt.Key_Escape) { dismiss(); return true }
    if (event.key === Qt.Key_Backspace) { back(); return true }
    var key = event.key === Qt.Key_Down ? "j" : event.key === Qt.Key_Up ? "k" : event.text
    if (awaitingG) {
      awaitingG = false
      if (goKeys[key]) { goKeys[key](); return true }
    }
    if (key === "g") { awaitingG = true; return true }
    if (pageKeys[key]) { pageKeys[key](); return true }
    if (!commitKeys[key] || !activeList) return false
    var commit = activeList.selectedCommit
    if (!commit && key !== "j" && key !== "k") return false
    commitKeys[key](activeList, commit)
    return true
  }

  // --- Window -------------------------------------------------------------------

  FloatingWindow {
    id: window
    visible: root.opened
    title: "dev-null"
    color: Color.background
    implicitWidth: 1220
    implicitHeight: 800
    minimumSize: Qt.size(760, 500)

    onVisibleChanged: if (!visible && root.opened) root.dismiss()

    FocusScope {
      id: scope
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) { event.accepted = root.handleKey(event) }

      // --- Sections ---------------------------------------------------------------

      Column {
        id: nav
        anchors { left: parent.left; top: parent.top; bottom: statusBar.top }
        width: Style.space(210)
        topPadding: Style.space(20)
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        spacing: Style.space(3)

        Row {
          leftPadding: Style.space(10)
          spacing: Style.space(2)
          Mono { text: "/dev"; font.pixelSize: Style.font.subtitle + 6; font.bold: true }
          Mono { text: "/"; color: root.laneColor(0); font.pixelSize: Style.font.subtitle + 6; font.bold: true }
          Mono { text: "null"; font.pixelSize: Style.font.subtitle + 6; font.bold: true }
        }
        Mono {
          leftPadding: Style.space(10)
          bottomPadding: Style.space(18)
          text: "a social network for devs"
          color: Color.muted
        }
        NavItem { icon: ""; label: "Log"; keys: "g l"; target: "log" }
        NavItem { icon: ""; label: "Notifications"; keys: "g n"; target: "notifications"; count: root.unread }
        NavItem { icon: ""; label: "Starred"; keys: "g s"; target: "starred" }
        NavItem { icon: ""; label: "Profile"; keys: "g p"; target: "profile" }
      }

      VLine { anchors.left: nav.right }

      Item {
        id: middle
        anchors { left: nav.right; leftMargin: 1; right: aside.visible ? aside.left : parent.right; top: parent.top; bottom: statusBar.top }

        // --- Log ------------------------------------------------------------------

        Item {
          anchors.fill: parent
          visible: root.page === "log"

          Row {
            id: tabs
            width: parent.width
            height: Style.space(44)
            Repeater {
              model: [
                { log: "following", key: "1" },
                { log: "latest", key: "2" },
                { log: "trending", key: "3" }
              ]
              Item {
                id: tab
                required property var modelData
                readonly property bool current: feed.log === modelData.log
                width: tabs.width / 3
                height: tabs.height
                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Mono { text: tab.modelData.key; color: Color.muted; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                  Mono {
                    text: tab.modelData.log
                    color: tab.current ? Color.foreground : Color.muted
                    font.pixelSize: Style.font.body
                    font.bold: tab.current
                  }
                }
                Rectangle {
                  visible: tab.current
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(80)
                  height: 3
                  radius: 1.5
                  color: root.primary
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: feed.switchLog(tab.modelData.log) }
              }
            }
          }
          HLine { anchors.top: tabs.bottom }

          CommitList {
            id: logList
            anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; topMargin: 1 }
            view: root
            commits: feed.commits
            hasMore: feed.nextCursor !== ""
            endLine: Model.listEnd({ loading: feed.loading, error: feed.lastError, more: hasMore,
                                     count: feed.commits.length, empty: "fatal: your " + feed.log + " log is empty" })
            onLoadMore: feed.loadMore()
            header: Composer {
              view: root
              Component.onCompleted: root.composerField = field
            }
          }
        }

        // --- Notifications ----------------------------------------------------------

        ListView {
          id: notices
          anchors.fill: parent
          visible: root.page === "notifications"
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: feed.notifications
          header: PageTitle { text: "Notifications" }
          delegate: NoticeRow {
            required property var modelData
            width: notices.width
            notification: modelData
            view: root
          }
          footer: EndLine {
            text: Model.listEnd({ count: feed.notifications.length,
                                  end: "That's the oldest notification. There's nothing before it.",
                                  empty: "$ cat /dev/notifications  # nothing yet" })
          }
        }

        // --- Starred -------------------------------------------------------------

        CommitList {
          id: starredList
          anchors.fill: parent
          visible: root.page === "starred"
          view: root
          commits: starred.items
          hasMore: starred.nextCursor !== ""
          endLine: Model.listEnd({ loading: starred.loading, error: starred.error, more: hasMore,
                                   count: starred.items.length, end: "That's every star you gave.",
                                   empty: "fatal: no stars yet. Press s on a commit you like." })
          onLoadMore: starred.more()
          header: PageTitle { text: "Starred" }
        }

        // --- Profile -------------------------------------------------------------

        ProfilePage {
          id: profilePage
          anchors.fill: parent
          visible: root.page === "profile"
          view: root
          service: feed
          username: root.profileName
        }
      }

      // --- You, and the keys ------------------------------------------------------

      Column {
        id: aside
        visible: window.width >= 1080
        anchors { right: parent.right; top: parent.top; bottom: statusBar.top }
        width: Style.space(280)
        padding: Style.space(20)
        spacing: Style.space(10)

        Row {
          spacing: Style.space(12)
          Avatar {
            size: Style.space(44)
            ring: root.laneColor(root.me.lane || 0)
            source: root.me.avatar_url || ""
            name: root.me.name || root.myUsername
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Mono { text: root.me.name || root.myUsername; font.pixelSize: Style.font.body; font.bold: true }
            Mono { text: "@" + root.myUsername; color: Color.muted }
          }
          TapHandler { onTapped: root.goTo("profile", root.myUsername) }
        }
        Mono {
          textFormat: Text.StyledText
          text: "<b>" + (root.me.commits_count || 0) + "</b>" + root.dimmed(" commits   ")
            + "<b>" + (root.me.following_count || 0) + "</b>" + root.dimmed(" following   ")
            + "<b>" + (root.me.followers_count || 0) + "</b>" + root.dimmed(" followers")
        }
        HLine { width: aside.width - aside.padding * 2 }
        Mono { topPadding: Style.space(4); text: "Keys"; font.pixelSize: Style.font.body; font.bold: true }
        Repeater {
          model: [
            ["j k", "move"], ["1 2 3", "following · latest · trending"], ["o", "replies"],
            ["s", "star"], ["r", "reply"], ["q", "quote"], ["c", "new commit"], ["p", "author's profile"],
            ["y", "copy link"], ["enter", "open on the site"], ["g l n s p", "log · notif. · starred · you"],
            ["⌫", "back"], ["R", "refresh"], ["esc", "close"]
          ]
          Row {
            required property var modelData
            spacing: Style.space(8)
            KeyCap { text: modelData[0] }
            Mono { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: Color.muted }
          }
        }
      }

      VLine { anchors.right: aside.left; visible: aside.visible }

      // Pictures at full size, over everything else.
      ImageViewer {
        id: viewer
        anchors.fill: parent
        z: 10
        view: root
      }

      // --- Status line, like a terminal's last row ------------------------------------

      Item {
        id: statusBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Style.space(28)
        HLine { anchors.top: parent.top }
        Mono {
          x: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - where.implicitWidth - Style.space(40)
          elide: Text.ElideRight
          text: root.status !== "" ? root.status : (root.awaitingG ? "g…" : "")
          color: root.statusFailed ? root.destructive : Color.foreground
        }
        Mono {
          id: where
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.StyledText
          text: "<font color='" + root.primary + "'>" + root.esc(root.page === "profile" ? "@" + root.profileName : root.page === "log" ? feed.log : root.page) + "</font>"
            + root.dimmed(feed.updatedAt !== "" ? "  ·  updated " + Model.ageFor(feed.updatedAt, root.now) : "")
        }
      }
    }
  }

  // --- Building blocks ------------------------------------------------------------

  component HLine: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: root.railColor
  }

  component VLine: Rectangle {
    anchors.top: parent.top
    anchors.bottom: statusBar.top
    width: 1
    color: root.railColor
  }

  component PageTitle: Item {
    property alias text: title.text
    width: ListView.view ? ListView.view.width : 0
    height: Style.space(56)
    Mono { id: title; x: Style.space(20); anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Style.font.subtitle + 2; font.bold: true }
    HLine { anchors.bottom: parent.bottom }
  }

  component EndLine: Item {
    property alias text: line.text
    width: ListView.view ? ListView.view.width : 0
    height: Style.space(52)
    Mono { id: line; anchors.centerIn: parent; color: Color.muted }
  }

  component KeyCap: Rectangle {
    property alias text: cap.text
    width: Math.max(Style.space(64), cap.implicitWidth + Style.space(10))
    height: cap.implicitHeight + Style.space(4)
    radius: Style.space(4)
    color: "transparent"
    border.width: 1
    border.color: root.railColor
    Mono { id: cap; anchors.centerIn: parent; font.pixelSize: Style.font.caption }
  }

  component NavItem: Rectangle {
    id: item
    property string icon
    property string label
    property string keys
    property string target
    property int count: 0
    readonly property bool current: root.page === target && (target !== "profile" || root.profileName === root.myUsername)
    width: nav.width - nav.leftPadding - nav.rightPadding
    height: Style.space(38)
    radius: Style.space(8)
    color: current ? Qt.rgba(root.primary.r, root.primary.g, root.primary.b, 0.14)
      : hover.hovered ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06) : "transparent"
    Row {
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)
      Mono { text: item.icon; color: item.current ? root.primary : Color.muted; font.pixelSize: Style.font.body + 2; anchors.verticalCenter: parent.verticalCenter }
      Mono { text: item.label; color: item.current ? root.primary : Color.foreground; font.pixelSize: Style.font.body; font.bold: item.current }
    }
    Rectangle {
      visible: item.count > 0
      anchors.right: keyText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, badge.implicitWidth + Style.space(8))
      height: badge.implicitHeight + Style.space(2)
      radius: height / 2
      color: root.primary
      Mono { id: badge; anchors.centerIn: parent; text: item.count; color: Color.background; font.pixelSize: Style.font.caption; font.bold: true }
    }
    Mono {
      id: keyText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: item.keys
      color: Color.muted
      font.pixelSize: Style.font.caption
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.goTo(item.target, item.target === "profile" ? root.myUsername : "") }
  }
}

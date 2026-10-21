import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The full view behind Open: dev-null's home as a terminal would draw it.
// Sections on the left, the log as a commit graph in the middle, who you are
// and the keys on the right. Colours and font are the Omarchy theme's, the
// author lanes included, so it follows `omarchy theme set`.
//
// The shell mounts this only while it is summoned, so its own Service polls
// only while it is on screen.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "zangetsu.devnull"

  // --- Look: everything comes from the theme ---------------------------------

  readonly property color foreground: Color.foreground
  readonly property color dim: Color.muted
  readonly property color railColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property string fontFamily: Style.font.family
  property var lanes: []
  property double now: Date.now()

  function laneColor(index) { return lanes[index] || Color.accent }
  function esc(text) {
    return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
  function dimmed(text) { return "<font color='" + dim + "'>" + esc(text) + "</font>" }

  // The lanes are the theme's orange, green, magenta, cyan, red and yellow.
  // Read again whenever the shell's own colours change, i.e. on a theme switch.
  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.lanes = Model.lanesFrom(text(), Color.accent)
  }
  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
    function onBackgroundChanged() { themeColors.reload() }
  }

  // --- State --------------------------------------------------------------------

  // "log" or "notifications".
  property string page: "log"
  property string selectedId: ""
  property string replyingTo: ""
  // Per commit id, not per row: the feed is replaced on every refresh.
  property var drafts: ({})
  property string composerText: ""
  property var quoting: null
  property string status: ""
  property bool awaitingG: false
  // The composer lives in the list header; this is how keys reach it.
  property var composerField: null

  readonly property int selectedIndex: {
    for (var i = 0; i < feed.commits.length; i++) if (feed.commits[i].id === selectedId) return i
    return feed.commits.length > 0 ? 0 : -1
  }
  readonly property var selectedCommit: selectedIndex >= 0 ? feed.commits[selectedIndex] : null
  readonly property int unread: feed.notifications.filter(function (n) { return !n.read_at }).length

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
    onReplyStatusChanged: root.say(replyStatus)
    onCommitStatusChanged: root.say(commitStatus)
    onCommitDone: function (answer) {
      if (answer.error) return
      root.composerText = ""
      root.quoting = null
    }
  }

  // --- What the rows and keys call (LogRow only talks to these) ---------------

  function threadFor(id) { return feed.threads[id] || null }
  function toggleStar(id) { feed.toggleStar(id) }
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
    focusComposer()
  }
  function focusComposer() { if (composerField) composerField.forceActiveFocus() }
  function openOnSite(url) { if (url) Quickshell.execDetached(["xdg-open", url]) }
  function copyLink(row) {
    Quickshell.execDetached(["wl-copy", row.url])
    say("Copied link to " + row.hash)
  }
  function say(text) {
    status = text
    if (text) statusClear.restart()
  }

  function postComposer() {
    if (composerText.trim() === "" || Model.charsLeft(composerText) < 0) return
    feed.postCommit(composerText, quoting ? quoting.id : "")
  }

  function showPage(name) {
    page = name
    scope.forceActiveFocus()
  }

  function move(step) {
    if (feed.commits.length === 0) return
    var next = Math.max(0, Math.min(feed.commits.length - 1, selectedIndex + step))
    selectedId = feed.commits[next].id
    list.positionViewAtIndex(next, ListView.Contain)
  }

  // --- Host --------------------------------------------------------------------

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (shell && shell.bar && typeof shell.bar.hideBarWidget === "function")
      shell.bar.hideBarWidget(pluginId)
    selectedId = String(payload.commit || "")
    page = "log"
    now = Date.now()
    opened = true
    feed.openPanel()
    feed.dispatch("profile")
    Qt.callLater(function () { scope.forceActiveFocus() })
  }

  function close() {
    opened = false
    replyingTo = ""
    feed.closePanel()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // --- Keys ---------------------------------------------------------------------

  readonly property var keyActions: ({
    "j": function () { root.move(1) },
    "k": function () { root.move(-1) },
    "1": function () { feed.switchLog("following") },
    "2": function () { feed.switchLog("latest") },
    "3": function () { feed.switchLog("trending") },
    "s": function () { if (root.selectedCommit) root.toggleStar(root.selectedCommit.id) },
    "r": function () { if (root.selectedCommit) root.toggleReply(root.selectedCommit.id) },
    "q": function () { if (root.selectedCommit) root.startQuote(root.selectedCommit) },
    "o": function () { if (root.selectedCommit) root.toggleThread(root.selectedCommit.id) },
    "y": function () { if (root.selectedCommit) root.copyLink(Model.rowFor(root.selectedCommit)) },
    "c": function () { root.showPage("log"); root.focusComposer() },
    "R": function () { feed.refresh() },
    "\r": function () { if (root.selectedCommit) root.openOnSite(root.selectedCommit.html_url) }
  })
  // `g` then a letter goes somewhere, as on the site.
  readonly property var goActions: ({
    "l": function () { root.showPage("log") },
    "n": function () { root.showPage("notifications") }
  })

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) { dismiss(); return true }
    if (event.key === Qt.Key_Down) { move(1); return true }
    if (event.key === Qt.Key_Up) { move(-1); return true }
    var key = event.text
    if (awaitingG) {
      awaitingG = false
      if (goActions[key]) { goActions[key](); return true }
    }
    if (key === "g") { awaitingG = true; return true }
    if (page !== "log" && key !== "c") return false
    if (!keyActions[key]) return false
    keyActions[key]()
    return true
  }

  // --- Window -------------------------------------------------------------------

  FloatingWindow {
    id: window
    visible: root.opened
    title: "dev-null"
    color: Color.background
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(720, 480)

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
        width: Style.space(190)
        topPadding: Style.space(16)
        spacing: Style.space(2)

        Mono {
          x: Style.space(16)
          text: "/dev/null"
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Mono {
          x: Style.space(16)
          bottomPadding: Style.space(14)
          text: "a social network for devs"
          color: root.dim
          font.pixelSize: Style.font.caption
        }
        NavItem { label: "Log"; key: "g l"; target: "log" }
        NavItem { label: "Notifications"; key: "g n"; target: "notifications"; count: root.unread }
      }

      VLine { anchors.left: nav.right }

      // --- The log ----------------------------------------------------------------

      Item {
        id: middle
        anchors { left: nav.right; right: aside.visible ? aside.left : parent.right; top: parent.top; bottom: statusBar.top }

        Row {
          id: tabs
          visible: root.page === "log"
          width: parent.width
          height: visible ? Style.space(36) : 0
          Repeater {
            model: [
              { log: "following", label: "following", key: "1" },
              { log: "latest", label: "latest", key: "2" },
              { log: "trending", label: "trending", key: "3" }
            ]
            Item {
              width: tabs.width / 3
              height: tabs.height
              readonly property bool current: feed.log === modelData.log
              Mono {
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: root.dimmed("[" + modelData.key + "] ") + modelData.label
                color: parent.current ? root.foreground : root.dim
                font.pixelSize: Style.font.body
                font.bold: parent.current
              }
              Rectangle {
                visible: parent.current
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                color: Color.accent
              }
              TapHandler { onTapped: feed.switchLog(modelData.log) }
            }
          }
        }
        HLine { anchors.top: tabs.bottom; visible: tabs.visible }

        ListView {
          id: list
          visible: root.page === "log"
          anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; topMargin: 1 }
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: feed.commits

          header: Composer {}

          delegate: LogRow {
            required property int index
            required property var modelData
            width: list.width
            commit: modelData
            view: root
            selected: index === root.selectedIndex
            laneAbove: index > 0 ? root.laneColor(Model.laneOf(feed.commits[index - 1])) : root.railColor
            TapHandler { onTapped: { root.selectedId = modelData.id; scope.forceActiveFocus() } }
          }

          footer: Item {
            width: list.width
            height: Style.space(44)
            Mono {
              anchors.centerIn: parent
              text: feed.loading ? "loading…"
                : feed.lastError !== "" ? "fatal: " + feed.lastError
                : feed.nextCursor !== "" ? "older…"
                : feed.commits.length > 0 ? "That's the root commit. There's nothing before it."
                : "fatal: your " + feed.log + " log is empty"
              color: feed.lastError !== "" ? Color.urgent : root.dim
            }
            TapHandler { onTapped: feed.loadMore() }
          }
        }

        // --- What happened to you ---------------------------------------------------

        ListView {
          id: notices
          visible: root.page === "notifications"
          anchors { fill: parent; margins: Style.space(16) }
          clip: true
          spacing: Style.space(8)
          model: feed.notifications
          header: Mono {
            bottomPadding: Style.space(10)
            text: "Notifications"
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          delegate: Mono {
            required property var modelData
            width: notices.width
            text: Model.summaryFor(modelData)
            color: modelData.read_at ? root.dim : root.foreground
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
          footer: Mono {
            topPadding: Style.space(12)
            text: feed.notifications.length > 0
              ? "That's the oldest notification. There's nothing before it."
              : "$ cat /dev/notifications  # nothing yet"
            color: root.dim
          }
        }
      }

      // --- You, and the keys ------------------------------------------------------

      Column {
        id: aside
        visible: window.width >= 1040
        anchors { right: parent.right; top: parent.top; bottom: statusBar.top }
        width: Style.space(270)
        padding: Style.space(18)
        spacing: Style.space(8)

        Mono {
          text: root.esc(feed.me.name || feed.username || "")
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Mono {
          textFormat: Text.StyledText
          text: "<font color='" + root.laneColor(feed.me.lane || 0) + "'>●</font> " + root.dimmed("@" + (feed.me.username || feed.username))
        }
        Mono {
          bottomPadding: Style.space(8)
          textFormat: Text.StyledText
          text: (feed.me.commits_count || 0) + root.dimmed(" commits  ")
            + (feed.me.following_count || 0) + root.dimmed(" following  ")
            + (feed.me.followers_count || 0) + root.dimmed(" followers")
        }
        HLine { width: aside.width - aside.padding * 2 }
        Mono { topPadding: Style.space(6); text: "keys"; font.bold: true }
        Repeater {
          model: [
            ["j k", "move between commits"], ["1 2 3", "following · latest · trending"],
            ["o", "show or hide replies"], ["s", "star"], ["r", "reply"], ["q", "quote"],
            ["c", "new commit"], ["y", "copy link"], ["enter", "open on the site"],
            ["g l  g n", "log · notifications"], ["R", "refresh"], ["esc", "close"]
          ]
          Row {
            Mono { width: Style.space(76); text: modelData[0]; font.bold: true }
            Mono { width: aside.width - aside.padding * 2 - Style.space(76); text: modelData[1]; color: root.dim; elide: Text.ElideRight }
          }
        }
      }

      VLine { anchors.right: aside.left; visible: aside.visible }

      // --- Status line, like a terminal's last row ------------------------------------

      Item {
        id: statusBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Style.space(26)
        HLine { anchors.top: parent.top }
        Mono {
          x: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - updated.implicitWidth - Style.space(36)
          elide: Text.ElideRight
          text: root.status !== "" ? root.status : (root.awaitingG ? "g…" : "")
        }
        Mono {
          id: updated
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: feed.log + (feed.updatedAt !== "" ? " · updated " + Model.ageFor(feed.updatedAt, root.now) : "")
          color: root.dim
        }
      }
    }
  }

  // --- Building blocks ------------------------------------------------------------

  component Mono: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

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

  component NavItem: Rectangle {
    id: item
    property string label
    property string key
    property string target
    property int count: 0
    readonly property bool current: root.page === target
    width: nav.width
    height: Style.space(30)
    color: current ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
    Rectangle { visible: item.current; width: 2; height: parent.height; color: Color.accent }
    Mono {
      x: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: item.label + (item.count > 0 ? "  " + item.count : "")
      color: item.current ? root.foreground : root.dim
      font.pixelSize: Style.font.body
    }
    Mono {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: item.key
      color: root.dim
      font.pixelSize: Style.font.caption
    }
    TapHandler { onTapped: root.showPage(item.target) }
  }

  // The staged commit at the top of the log: a hollow node, then the field.
  component Composer: Item {
    width: list.width
    height: field.height + hint.height + Style.space(24)

    Rectangle {
      x: Style.space(15) - width / 2
      y: Style.space(14)
      width: Style.space(10)
      height: width
      radius: width / 2
      color: root.composerText !== "" ? root.laneColor(feed.me.lane || 0) : Color.background
      border.width: 2
      border.color: root.laneColor(feed.me.lane || 0)
    }

    TextArea {
      id: field
      x: Style.space(30)
      y: Style.space(8)
      width: parent.width - x - Style.space(12)
      placeholderText: root.quoting ? "add your take on " + Model.rowFor(root.quoting).handle + "'s commit…"
                                    : "What did you ship?"
      wrapMode: TextEdit.Wrap
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      background: null
      text: root.composerText
      onTextChanged: root.composerText = text
      Component.onCompleted: root.composerField = field
      Keys.onPressed: function (event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
          root.postComposer()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.quoting = null
          scope.forceActiveFocus()
          event.accepted = true
        }
      }
    }

    Mono {
      id: hint
      x: field.x
      anchors.top: field.bottom
      width: field.width
      textFormat: Text.StyledText
      text: (root.quoting ? root.dimmed("❝ quoting " + Model.rowFor(root.quoting).handle + " " + Model.rowFor(root.quoting).hash + " · esc drops it   ") : "")
        + root.dimmed(Model.charsLeft(root.composerText) + "  ·  ctrl+enter commits")
      horizontalAlignment: Text.AlignRight
    }
  }

}

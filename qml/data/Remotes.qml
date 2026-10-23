import QtQuick
import "Model.js" as Model

// The private messages: the inbox, and whichever thread is open.
//
// It keeps its own state rather than growing Service, which already carries
// the log, the notifications and the pairing. Both run the same bridge.
QtObject {
  id: root

  required property var service
  property string myUsername: ""

  property string tab: "open"
  property string search: ""
  property var conversations: []
  property int unread: 0
  property int fetched: 0
  property bool loading: false

  // The open thread, by the partner's handle. Empty means the inbox.
  property string partner: ""
  property var messages: []
  property bool canWrite: true
  property string draft: ""
  property string lastError: ""

  readonly property var rows: {
    var out = []
    for (var i = 0; i < conversations.length; i++) {
      var row = Model.remoteFor(conversations[i], root.myUsername)
      if (row) out.push(row)
    }
    return out
  }

  readonly property var lines: {
    var out = []
    for (var i = 0; i < messages.length; i++) {
      var line = Model.messageFor(messages[i], root.myUsername)
      if (line) out.push(line)
    }
    return out
  }

  function run(args, done) { service.run(args, done) }

  function refresh() {
    root.loading = true
    var args = ["remotes", "--tab", root.tab]
    if (root.search !== "") args = args.concat(["--q", root.search])
    root.run(args, function (answer) {
      root.loading = false
      if (answer.error) { root.lastError = Model.errorLine(answer); return }
      root.lastError = ""
      root.conversations = answer.conversations || []
      root.unread = answer.unread_count || 0
      root.fetched = answer.fetched_count || 0
    })
  }

  function switchTab(name) {
    if (Model.INBOX_TABS.indexOf(name) < 0 || name === root.tab) return
    root.tab = name
    root.conversations = []
    root.refresh()
  }

  function find(text) {
    root.search = text
    root.refresh()
  }

  // Opening a thread marks it read, exactly as opening it on the website does.
  function open(username) {
    root.partner = username
    root.messages = []
    root.loadThread()
  }

  function close() {
    root.partner = ""
    root.messages = []
  }

  function loadThread() {
    if (root.partner === "") return
    root.loading = true
    root.run(["thread", root.partner], function (answer) {
      root.loading = false
      if (answer.error) { root.lastError = Model.errorLine(answer); return }
      root.lastError = ""
      root.messages = answer.messages || []
      root.canWrite = answer.can_write !== false
      root.run(["read", root.partner], function () { root.refresh() })
    })
  }

  function send(body) {
    if (root.partner === "" || body.trim() === "") return
    root.run(["send", root.partner, body], function (answer) {
      if (answer.error) { root.lastError = Model.errorLine(answer); return }
      root.lastError = ""
      root.draft = ""
      root.loadThread()
    })
  }

  function react(messageId, reaction) {
    root.run(["react", String(messageId), reaction], function (answer) {
      if (!answer.error) root.loadThread()
    })
  }

  // A fetched request: take it into your conversations, or turn it away.
  function merge(username) { root.run(["merge", username], function () { root.refresh() }) }
  function drop(username) { root.run(["drop", username], function () { root.refresh() }) }
  function archive(username) { root.run(["archive", username], function () { root.refresh() }) }
  function muteRemote(username) { root.run(["mute-remote", username], function () { root.refresh() }) }
}

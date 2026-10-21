import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Holds what the panel draws and runs scripts/devnull to get it. Every decision
// about what to call, and about when the pairing is dead, lives in Model.js —
// this only carries it out.
QtObject {
  id: root

  property var settings: ({})

  property int unreadCount: 0
  property var commits: []
  property var notifications: []
  property string nextCursor: ""
  property bool loading: true
  property bool broken: false
  property string lastError: ""
  property string replyStatus: ""
  property bool panelOpen: false

  property int _authFailures: 0
  property string _scriptPath: Qt.resolvedUrl("scripts/devnull").toString().replace("file://", "")

  property Timer _timer: Timer {
    interval: Model.pollDelay(root.panelOpen, root.settings)
    running: !root.broken
    repeat: true
    onTriggered: root.tick()
  }

  signal failed(string line)

  function run(args, done) {
    var process = processComponent.createObject(root, { command: [root._scriptPath].concat(args) })
    process.finished.connect(function (answer) {
      process.destroy()
      if (answer && answer.error) {
        root._authFailures = Model.nextFailureCount(root._authFailures, answer)
        root.broken = Model.isBroken(root._authFailures)
        root.lastError = Model.errorLine(answer)
        root.failed(root.lastError)
      } else {
        root._authFailures = Model.nextFailureCount(root._authFailures, null)
        root.lastError = ""
      }
      if (done) done(answer)
    })
    process.running = true
  }

  function tick() {
    var calls = Model.tickCalls(root.panelOpen, root.broken)
    for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
  }

  function dispatch(name) {
    if (name === "me") {
      root.run(["me"], function (answer) {
        if (!answer.error) root.unreadCount = answer.unread_notifications_count || 0
        root.loading = false
      })
    } else if (name === "feed") {
      root.run(["feed"], function (answer) {
        if (!answer.error) {
          root.commits = answer.commits || []
          root.nextCursor = answer.next_cursor || ""
        }
        root.loading = false
      })
    } else if (name === "notifications") {
      root.run(["notifications"], function (answer) {
        if (!answer.error) {
          root.notifications = answer.notifications || []
          // They are read now, upstream too: the badge must not claim otherwise.
          root.unreadCount = 0
        }
      })
    }
  }

  function openPanel() {
    root.panelOpen = true
    if (root.broken) return
    var calls = Model.openCalls()
    for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
  }

  function closePanel() {
    root.panelOpen = false
  }

  function refresh() {
    root.tick()
  }

  function loadMore() {
    if (!root.nextCursor || root.broken) return
    root.run(["feed", "--cursor", root.nextCursor], function (answer) {
      if (answer.error) return
      root.commits = root.commits.concat(answer.commits || [])
      root.nextCursor = answer.next_cursor || ""
    })
  }

  function commitIndex(id) {
    for (var i = 0; i < root.commits.length; i++) if (root.commits[i].id === id) return i
    return -1
  }

  function replaceCommit(index, commit) {
    var copy = root.commits.slice()
    copy[index] = commit
    root.commits = copy
  }

  function toggleStar(id) {
    var index = root.commitIndex(id)
    if (index < 0) return
    var original = root.commits[index]
    var wanted = !original.starred
    // Applied first so the tap feels immediate, put back if the server refuses.
    root.replaceCommit(index, Model.withStar(original, wanted))
    root.run([wanted ? "star" : "unstar", id], function (answer) {
      var at = root.commitIndex(id)
      if (at < 0) return
      if (answer.error) root.replaceCommit(at, original)
      else if (answer.stars_count !== undefined) {
        var fresh = Model.withStar(root.commits[at], answer.starred === true)
        fresh.stars_count = answer.stars_count
        root.replaceCommit(at, fresh)
      }
    })
  }

  function sendReply(id, body) {
    root.replyStatus = ""
    root.run(["reply", id, body], function (answer) {
      if (answer.error) root.replyStatus = Model.errorLine(answer)
      else if (answer.status === "pending") root.replyStatus = "Sent — held for moderation."
      else root.replyStatus = "Sent."
    })
  }

  property Component processComponent: Component {
    Process {
      signal finished(var answer)
      stdout: StdioCollector {
        onStreamFinished: {
          var answer = {}
          try { answer = JSON.parse(text) } catch (e) { answer = { error: text, kind: "http" } }
          finished(answer)
        }
      }
    }
  }
}

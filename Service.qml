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
  property string username: ""
  // /me's user, for the profile line beside the log: name, lane, counts.
  property var me: ({})
  // Which log the feed shows: latest, following or trending.
  property string log: "latest"
  // Threads opened in place, by commit id: { replies, nextCursor, loading }.
  property var threads: ({})
  property string commitStatus: ""
  // When the feed last landed, for the "updated …" line under the list.
  property string updatedAt: ""
  property bool loading: true
  property bool broken: false
  property string lastError: ""
  property string replyStatus: ""
  property bool panelOpen: false

  property int _authFailures: 0
  // True once older pages were loaded: the timer then leaves the feed alone
  // rather than replacing everything he scrolled to with page one.
  property bool expanded: false
  property string _scriptPath: Qt.resolvedUrl("scripts/devnull").toString().replace("file://", "")

  property Timer _timer: Timer {
    interval: Model.pollDelay(root.panelOpen, root.settings)
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  signal replyDone(string id, var answer)

  function run(args, done) {
    var process = processComponent.createObject(root, { command: [root._scriptPath].concat(args) })
    process.finished.connect(function (answer) {
      process.destroy()
      if (answer && answer.error) {
        root._authFailures = Model.nextFailureCount(root._authFailures, answer)
        root.broken = Model.isBroken(root._authFailures)
        root.lastError = Model.errorLine(answer)
      } else {
        root._authFailures = Model.nextFailureCount(root._authFailures, null)
        root.lastError = ""
      }
      if (done) done(answer)
    })
    process.running = true
  }

  function tick() {
    var calls = Model.tickCalls(root.panelOpen, root.broken, root.expanded)
    for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
  }

  function dispatch(name) {
    if (name === "me") {
      root.run(["me"], function (answer) {
        if (!answer.error) {
          root.unreadCount = answer.unread_notifications_count || 0
          root.username = (answer.data || {}).username || root.username
          if (answer.data) root.me = answer.data
        }
        root.loading = false
      })
    } else if (name === "feed") {
      var asked = root.log
      root.run(["feed", "--log", asked], function (answer) {
        // A tab switched while this was in flight: its own call is on the way.
        if (asked !== root.log) return
        if (!answer.error) {
          root.commits = answer.commits || []
          root.nextCursor = answer.next_cursor || ""
          root.expanded = false
          root.updatedAt = new Date().toISOString()
        }
        root.loading = false
      })
    } else if (name === "profile") {
      root.run(["me"], function (answer) {
        if (!answer.error && answer.data) root.me = answer.data
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
    root.expanded = false
    // Broken, this is a single probe: a successful answer clears the failure
    // count, so re-pairing is noticed without restarting the shell.
    var wasBroken = root.broken
    var calls = Model.openCalls(root.broken)
    for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
    if (wasBroken) root.recoveryCheck.restart()
  }

  // Gives the probe time to answer before deciding whether it is alive again.
  property Timer recoveryCheck: Timer {
    interval: 1500
    onTriggered: if (!root.broken && root.panelOpen) {
      var calls = Model.openCalls(false)
      for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
    }
  }

  function closePanel() {
    root.panelOpen = false
  }

  function refresh() {
    root.tick()
  }

  function loadMore() {
    if (!root.nextCursor || root.broken) return
    var asked = root.log
    root.run(["feed", "--log", asked, "--cursor", root.nextCursor], function (answer) {
      if (answer.error || asked !== root.log) return
      root.commits = root.commits.concat(answer.commits || [])
      root.nextCursor = answer.next_cursor || ""
      root.expanded = true
    })
  }

  function switchLog(log) {
    if (log === root.log) return
    root.log = log
    root.commits = []
    root.nextCursor = ""
    root.expanded = false
    root.threads = ({})
    root.dispatch("feed")
  }

  // A commit changed wherever it is drawn: on the log, in a preview, in a thread.
  function changeCommit(id, change) {
    root.commits = Model.mapCommit(root.commits, id, change)
    var next = ({})
    for (var key in root.threads) {
      var thread = root.threads[key]
      next[key] = { replies: Model.mapCommit(thread.replies, id, change),
                    nextCursor: thread.nextCursor, loading: thread.loading }
    }
    root.threads = next
  }

  function findCommit(id) {
    var found = Model.findCommit(root.commits, id)
    for (var key in root.threads) found = found || Model.findCommit(root.threads[key].replies, id)
    return found
  }

  function toggleStar(id) {
    var original = root.findCommit(id)
    if (!original) return
    var wanted = !original.starred
    // Applied first so the tap feels immediate, put back if the server refuses.
    root.changeCommit(id, function (c) { return Model.withStar(c, wanted) })
    root.run([wanted ? "star" : "unstar", id], function (answer) {
      if (answer.error) root.changeCommit(id, function (c) { return Model.withStar(c, !wanted) })
      else if (answer.stars_count !== undefined) root.changeCommit(id, function (c) {
        var fresh = Model.withStar(c, answer.starred === true)
        fresh.stars_count = answer.stars_count
        return fresh
      })
    })
  }

  // Opens a thread in place, or closes it when it is open.
  function toggleThread(id) {
    var next = ({})
    for (var key in root.threads) if (key !== id) next[key] = root.threads[key]
    if (root.threads[id]) { root.threads = next; return }
    next[id] = { replies: [], nextCursor: "", loading: true }
    root.threads = next
    root.loadThread(id, "")
  }

  function loadThread(id, cursor) {
    root.run(cursor ? ["replies", id, "--cursor", cursor] : ["replies", id], function (answer) {
      var thread = root.threads[id]
      if (!thread) return
      var next = ({})
      for (var key in root.threads) next[key] = root.threads[key]
      next[id] = {
        replies: answer.error ? thread.replies : thread.replies.concat(answer.replies || []),
        nextCursor: answer.error ? "" : (answer.next_cursor || ""),
        loading: false
      }
      root.threads = next
    })
  }

  signal commitDone(var answer)

  // A new commit, or a quote when quotedId is set. The log reloads once it lands.
  function postCommit(body, quotedId) {
    root.commitStatus = ""
    var args = quotedId ? ["commit", body, "--quote", quotedId] : ["commit", body]
    root.run(args, function (answer) {
      if (answer.error) root.commitStatus = Model.errorLine(answer)
      else {
        root.commitStatus = "[log " + (answer.short_hash || "") + "] " + String(answer.body || body).split("\n")[0]
          + (answer.status === "pending" ? "  (held for moderation)" : "")
        root.dispatch("feed")
      }
      root.commitDone(answer)
    })
  }

  function sendReply(id, body) {
    root.replyStatus = ""
    root.run(["reply", id, body], function (answer) {
      if (answer.error) root.replyStatus = Model.errorLine(answer)
      else if (answer.status === "pending") root.replyStatus = "Sent — held for moderation."
      else root.replyStatus = "Sent."
      // The reply shows up where it was written: reload that thread if it is open.
      if (!answer.error && root.threads[id]) {
        root.toggleThread(id)
        root.toggleThread(id)
      }
      root.replyDone(id, answer)
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

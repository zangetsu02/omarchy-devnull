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
  // When the feed last landed, for the "updated …" line under the list.
  property string updatedAt: ""
  property bool loading: true
  property bool broken: false
  // Never connected. Not a failure: the panel reads the public feed and offers
  // the connection, rather than showing a red line about a key nobody made yet.
  property bool signedOut: false
  property string lastError: ""
  property bool panelOpen: false

  property int _authFailures: 0
  // True once older pages were loaded: the timer then leaves the feed alone
  // rather than replacing everything scrolled to with page one.
  property bool expanded: false
  property string _scriptPath: Qt.resolvedUrl("../../scripts/devnull").toString().replace("file://", "")

  property Timer _timer: Timer {
    interval: Model.pollDelay(root.panelOpen, root.settings)
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  signal replyDone(string id, var answer)
  signal commitDone(var answer)
  // One line worth showing to the user, e.g. "[log abc1234] shipped it".
  signal told(string text, bool failed)

  function run(args, done) {
    var process = processComponent.createObject(root, { command: [root._scriptPath].concat(args) })
    process.finished.connect(function (answer) {
      process.destroy()
      if (answer && answer.error) {
        root._authFailures = Model.nextFailureCount(root._authFailures, answer)
        root.broken = Model.isBroken(root._authFailures)
        var wasSignedOut = root.signedOut
        root.signedOut = answer.kind === "unpaired"
        root.lastError = Model.errorLine(answer)
        // Found out just now: fetch the public feed at once rather than leaving
        // the panel blank until the next tick.
        if (root.signedOut && !wasSignedOut) root.dispatch("publicFeed")
      } else {
        root._authFailures = Model.nextFailureCount(root._authFailures, null)
        root.signedOut = false
        root.lastError = ""
      }
      if (done) done(answer)
    })
    process.running = true
  }

  // Where the panel stands, as one value, so the rules can be asked in one way.
  function state() {
    return {
      panelOpen: root.panelOpen,
      broken: root.broken,
      expanded: root.expanded,
      signedOut: root.signedOut
    }
  }

  function tick() {
    var calls = Model.tickCalls(root.state())
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
    } else if (name === "publicFeed") {
      root.run(["feed", "--public"], function (answer) {
        if (!answer.error) {
          root.commits = answer.commits || []
          root.nextCursor = ""          // paging the public page is not offered
          root.expanded = false
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
    root.expanded = false
    // Broken, this is a single probe: a successful answer clears the failure
    // count, so re-pairing is noticed without restarting the shell.
    var wasBroken = root.broken
    var calls = Model.openCalls(root.state())
    for (var i = 0; i < calls.length; i++) root.dispatch(calls[i])
    if (wasBroken) root.recoveryCheck.restart()
  }

  // Gives the probe time to answer before deciding whether it is alive again.
  property Timer recoveryCheck: Timer {
    interval: 1500
    onTriggered: if (!root.broken && root.panelOpen) {
      var calls = Model.openCalls({ signedOut: root.signedOut })
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

  // A commit changed wherever it is drawn: on the log, in a preview, in a
  // thread here, and — through commitChanged — in every Pager listening.
  signal commitChanged(string id, var change)

  function changeCommit(id, change) {
    root.commits = Model.mapCommit(root.commits, id, change)
    var next = ({})
    for (var key in root.threads)
      next[key] = Model.merged(root.threads[key], { replies: Model.mapCommit(root.threads[key].replies, id, change) })
    root.threads = next
    root.commitChanged(id, change)
  }

  // `starred` is what the caller sees now, so a commit on any list can be starred.
  function toggleStar(id, starred) {
    var wanted = !starred
    // Applied first so the tap feels immediate, put back if the server refuses.
    root.changeCommit(id, function (c) { return Model.withStar(c, wanted) })
    root.run([wanted ? "star" : "unstar", id], function (answer) {
      if (answer.error) root.changeCommit(id, function (c) { return Model.withStar(c, !wanted) })
      // The server's count wins over the guess.
      else if (answer.stars_count !== undefined) root.changeCommit(id, function (c) {
        return Model.merged(c, { starred: answer.starred === true, stars_count: answer.stars_count })
      })
    })
  }

  signal userChanged(string username, var change)

  function follow(username, wanted) {
    root.userChanged(username, function (user) { return Model.withFollow(user, wanted) })
    root.run([wanted ? "follow" : "unfollow", username], function (answer) {
      if (answer.error) root.userChanged(username, function (user) { return Model.withFollow(user, !wanted) })
    })
  }

  // A profile's level, achievements and commit activity, handed to `done`.
  function fetchStanding(username, done) {
    root.run(["standing", username], function (answer) { if (!answer.error) done(answer) })
  }

  // A profile, handed to `done` once it lands.
  function fetchUser(username, done) {
    root.run(["user", username], function (answer) { if (!answer.error) done(answer) })
  }

  // Opens a thread in place, or closes it when it is open.
  function toggleThread(id) {
    if (root.threads[id]) root.threads = Model.without(root.threads, id)
    else root.reloadThread(id)
  }

  function reloadThread(id) {
    root.setThread(id, { replies: [], nextCursor: "", loading: true })
    root.loadThread(id, "")
  }

  function setThread(id, thread) {
    var change = {}
    change[id] = thread
    root.threads = Model.merged(root.threads, change)
  }

  function loadThread(id, cursor) {
    root.run(cursor ? ["replies", id, "--cursor", cursor] : ["replies", id], function (answer) {
      var thread = root.threads[id]
      if (!thread) return
      root.setThread(id, {
        replies: answer.error ? thread.replies : thread.replies.concat(answer.replies || []),
        nextCursor: answer.error ? "" : (answer.next_cursor || ""),
        loading: false
      })
    })
  }

  // A new commit, or a quote when quotedId is set. The log reloads once it lands.
  function postCommit(body, quotedId) {
    var args = quotedId ? ["commit", body, "--quote", quotedId] : ["commit", body]
    root.run(args, function (answer) {
      if (answer.error) root.told(Model.errorLine(answer), true)
      else {
        root.told("[log " + (answer.short_hash || "") + "] " + String(answer.body || body).split("\n")[0]
          + (answer.status === "pending" ? "  (held for moderation)" : ""), false)
        root.dispatch("feed")
      }
      root.commitDone(answer)
    })
  }

  function sendReply(id, body) {
    root.run(["reply", id, body], function (answer) {
      if (answer.error) root.told(Model.errorLine(answer), true)
      else root.told(answer.status === "pending" ? "Sent — held for moderation." : "Sent.", false)
      // The reply shows up where it was written, if that thread is open.
      if (!answer.error && root.threads[id]) root.reloadThread(id)
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

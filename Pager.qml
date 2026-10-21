import QtQuick
import "Model.js" as Model

// One paged list from the bridge — starred, a profile's commits, its followers —
// so every section pages, reloads and keeps stars in step the same way.
// `args` is the bridge command, e.g. ["user-commits", "pptx704"].
QtObject {
  id: root

  required property var service
  property var args: []

  property var items: []
  property string nextCursor: ""
  property bool loading: false
  property string error: ""

  function reload() {
    if (root.args.length === 0) return
    root.items = []
    root.nextCursor = ""
    root.fetch("")
  }

  function more() {
    if (root.nextCursor !== "" && !root.loading) root.fetch(root.nextCursor)
  }

  function fetch(cursor) {
    var asked = root.args
    root.loading = true
    root.service.run(cursor ? asked.concat(["--cursor", cursor]) : asked, function (answer) {
      // The list was pointed somewhere else meanwhile: this answer is stale.
      if (asked !== root.args) return
      root.loading = false
      root.error = answer.error ? Model.errorLine(answer) : ""
      if (answer.error) return
      root.items = root.items.concat(answer.items || [])
      root.nextCursor = answer.next_cursor || ""
    })
  }

  onArgsChanged: reload()

  // A star given anywhere shows here too; a follow changes the people listed.
  property Connections _commits: Connections {
    target: root.service
    function onCommitChanged(id, change) { root.items = Model.mapCommit(root.items, id, change) }
    function onUserChanged(username, change) {
      root.items = root.items.map(function (item) { return item.username === username ? change(item) : item })
    }
  }
}

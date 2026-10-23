import QtQuick
import qs.Commons
import "../data"
import "../ui"
import "../data/Model.js" as Model

// One commit on its own: the commits it replies to above it on the same rail,
// then the commit, selected, with its replies already open — the site's
// commit page, drawn like the log.
Item {
  id: root

  required property var view
  required property var service
  property string commitId: ""

  readonly property alias commitList: list
  readonly property var focused: conversation.items.length > 0 ? conversation.items[conversation.items.length - 1] : null

  Pager {
    id: conversation
    service: root.service
    args: root.commitId !== "" ? ["show", root.commitId] : []
  }

  // Its replies open by themselves once it lands, as on the site.
  onFocusedChanged: {
    if (!focused) return
    list.selectedId = focused.id
    if ((focused.replies_count || 0) > 0 && !root.view.threadFor(focused.id)) root.view.toggleThread(focused.id)
  }

  CommitList {
    id: list
    anchors.fill: parent
    view: root.view
    commits: conversation.items
    endLine: Model.listEnd({ loading: conversation.loading, error: conversation.error, count: conversation.items.length,
                             end: root.focused ? root.focused.short_hash + " · " + Model.plural(root.focused.replies_count || 0, "reply", "replies") : "",
                             empty: "fatal: that commit is not there any more" })
    // The pane names itself in its own top border, as a box-drawn pane does.
    header: Item {
      width: list.width
      height: Style.space(34)
      FrameLine {
        x: Style.space(14)
        width: parent.width - Style.space(28)
        anchors.verticalCenter: parent.verticalCenter
        lineColor: root.view.railColor
        title: root.focused ? "commit " + root.focused.short_hash : "commit"
      }
      ActionButton {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        visible: !!root.focused
        icon: "↗"
        label: "O  on the site"
        onClicked: root.view.openOnSite(root.focused.html_url)
      }
    }
  }
}

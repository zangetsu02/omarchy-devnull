import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../ui"
import "../data/Model.js" as Model

// The private messages. The inbox on the left, the open thread on the right,
// and the composer under it. Drawn on the same character grid as the log: a
// message hangs off its author's lane, exactly as a commit does.
Item {
  id: root

  required property var view
  required property var remotes

  Metrics { id: grid }
  readonly property color line: view.railColor

  // --- The inbox ---------------------------------------------------------------

  Item {
    id: inbox
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    width: Math.min(Style.space(300), root.width * 0.38)

    FrameLine {
      id: inboxTop
      x: Style.space(10)
      width: parent.width - Style.space(20)
      height: grid.lineH
      lineColor: root.line
      title: root.remotes.tab + (root.remotes.unread > 0 ? "  " + root.remotes.unread : "")
    }

    Row {
      id: tabs
      y: inboxTop.y + inboxTop.height + Style.space(4)
      x: Style.space(14)
      spacing: Style.space(12)
      Repeater {
        model: Model.INBOX_TABS
        Mono {
          required property string modelData
          text: modelData
          font.pixelSize: grid.size
          color: modelData === root.remotes.tab ? Color.foreground : Color.muted
          font.bold: modelData === root.remotes.tab
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.remotes.switchTab(modelData) }
        }
      }
    }

    ListView {
      id: chats
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      anchors.top: tabs.bottom
      anchors.topMargin: Style.space(8)
      clip: true
      model: root.remotes.rows
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        required property var modelData
        width: chats.width
        height: who.implicitHeight + preview.implicitHeight + Style.space(18)

        Rectangle {
          anchors.fill: parent
          visible: modelData.username === root.remotes.partner
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
        }

        Avatar {
          id: face
          x: Style.space(14)
          y: Style.space(8)
          size: grid.cell * 2
          ring: root.view.laneColor(modelData.lane)
          source: modelData.avatar
          name: modelData.name
        }

        Mono {
          id: who
          x: face.x + face.width + grid.cell
          y: Style.space(7)
          width: parent.width - x - Style.space(30)
          elide: Text.ElideRight
          font.pixelSize: grid.size
          color: modelData.unread > 0 ? Color.foreground : Color.muted
          font.bold: modelData.unread > 0
          text: modelData.handle
        }

        Mono {
          id: preview
          x: who.x
          y: who.y + who.implicitHeight + 2
          width: who.width
          elide: Text.ElideRight
          color: Color.muted
          text: (modelData.mine ? "you: " : "") + modelData.preview
        }

        // Unread, as a count where the lane would put a node.
        Mono {
          visible: modelData.unread > 0
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          y: who.y
          font.pixelSize: grid.size
          color: root.view.primary
          text: String(modelData.unread)
        }

        TapHandler { onTapped: root.remotes.open(modelData.username) }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
      }

      footer: Mono {
        width: chats.width
        topPadding: Style.space(10)
        horizontalAlignment: Text.AlignHCenter
        color: Color.muted
        text: Model.listEnd({ loading: root.remotes.loading,
                              error: root.remotes.lastError,
                              count: root.remotes.rows.length,
                              empty: "$ cat /dev/remotes  # nobody yet" })
      }
    }
  }

  Rectangle {
    x: inbox.width
    width: 1
    height: parent.height
    color: root.line
  }

  // --- The open thread ---------------------------------------------------------

  Item {
    id: thread
    anchors { left: inbox.right; leftMargin: 1; right: parent.right; top: parent.top; bottom: parent.bottom }
    visible: root.remotes.partner !== ""

    FrameLine {
      id: threadTop
      x: Style.space(14)
      width: parent.width - Style.space(28)
      height: grid.lineH
      lineColor: root.line
      title: "@" + root.remotes.partner
    }

    ListView {
      id: lines
      anchors { left: parent.left; right: parent.right }
      anchors.top: threadTop.bottom
      anchors.bottom: composer.top
      anchors.topMargin: Style.space(6)
      clip: true
      model: root.remotes.lines
      verticalLayoutDirection: ListView.BottomToTop
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        required property var modelData
        width: lines.width
        height: body.implicitHeight + head.implicitHeight + Style.space(14)

        Rail {
          x: grid.cell * 2
          y: Style.space(4)
          rowHeight: parent.height - Style.space(4)
          metrics: grid
          cells: 2
          headColor: root.view.laneColor(modelData.lane)
          tailColor: root.view.laneColor(modelData.lane)
          head: ""
        }

        Avatar {
          id: mugshot
          x: grid.cell * 2 + grid.cell - implicitWidth / 2
          y: Style.space(4)
          size: grid.cell * 2
          ring: root.view.laneColor(modelData.lane)
          source: modelData.avatar
          name: modelData.name
        }

        Mono {
          id: head
          x: grid.cell * 6
          y: Style.space(4)
          width: parent.width - x - Style.space(16)
          elide: Text.ElideRight
          font.pixelSize: grid.size
          color: Color.muted
          text: (modelData.mine ? "you" : modelData.handle)
            + "   " + Model.ageFor(modelData.when, root.view.now)
        }

        TextEdit {
          id: body
          x: head.x
          y: head.y + head.implicitHeight + 2
          width: head.width
          readOnly: true
          selectByMouse: true
          text: modelData.body
          color: Color.foreground
          selectionColor: Qt.rgba(root.view.primary.r, root.view.primary.g, root.view.primary.b, 0.35)
          selectedTextColor: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
        }
      }
    }

    // --- Writing back ------------------------------------------------------------

    Item {
      id: composer
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: field.implicitHeight + Style.space(20)

      Rectangle { width: parent.width; height: 1; color: root.line }

      Mono {
        id: prompt
        x: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: grid.size
        color: root.remotes.canWrite ? root.view.primary : Color.muted
        text: root.remotes.canWrite ? ">" : "#"
      }

      TextField {
        id: field
        x: prompt.x + prompt.implicitWidth + grid.cell
        width: parent.width - x - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.remotes.canWrite
        background: null
        padding: 0
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        placeholderText: root.remotes.canWrite
          ? "write to @" + root.remotes.partner + "…"
          : "@" + root.remotes.partner + " does not take messages from you"
        placeholderTextColor: Color.muted
        text: root.remotes.draft
        onTextEdited: root.remotes.draft = text
        onAccepted: { root.remotes.send(text); text = "" }
      }
    }
  }

  // Nothing open: say which half is waiting for a click.
  Mono {
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: inbox.width / 2
    visible: root.remotes.partner === ""
    color: Color.muted
    text: "$ pick a conversation"
  }
}

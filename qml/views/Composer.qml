import QtQuick
import QtQuick.Controls
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// The staged commit at the top of the log: a hollow node in your lane that
// fills once there is something to commit, your avatar, the field, and the
// counter with the Commit button. Quoting puts the quoted commit under it.
Item {
  id: root

  required property var view
  readonly property alias field: field
  readonly property var me: view.me
  readonly property color lane: view.laneColor(me.lane || 0)
  readonly property int remaining: Model.charsLeft(view.composerText)
  readonly property bool ready: view.composerText.trim() !== "" && remaining >= 0
  readonly property real railWidth: Style.space(34)
  readonly property real pad: Style.space(14)

  width: ListView.view ? ListView.view.width : 0
  height: column.implicitHeight + pad * 2

  // The rail starts here, dashed until the commit is staged.
  Repeater {
    model: Math.ceil((root.height - node.y - node.height) / Style.space(8))
    Rectangle {
      required property int index
      x: root.railWidth / 2 - 1
      y: node.y + node.height + index * Style.space(8) + Style.space(2)
      width: 2
      height: Style.space(4)
      color: root.view.railColor
    }
  }
  Rectangle {
    id: node
    x: root.railWidth / 2 - width / 2
    y: root.pad + Style.space(11)
    width: Style.space(12)
    height: width
    radius: width / 2
    color: root.ready ? root.lane : Color.background
    border.width: 2
    border.color: root.lane
  }

  Avatar {
    id: avatar
    x: root.railWidth + Style.space(4)
    y: root.pad
    size: Style.space(34)
    source: root.me.avatar_url || ""
    name: root.me.name || ""
  }

  Column {
    id: column
    x: avatar.x + avatar.width + Style.space(10)
    y: root.pad
    width: root.width - x - Style.space(14)
    spacing: Style.space(8)

    TextArea {
      id: field
      width: column.width
      placeholderText: root.view.quoting ? "add your take…" : "What did you ship?"
      placeholderTextColor: Color.muted
      wrapMode: TextEdit.Wrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle + 2
      background: null
      padding: 0
      topPadding: Style.space(6)
      text: root.view.composerText
      onTextChanged: root.view.composerText = text
      Keys.onPressed: function (event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
          root.view.postComposer()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.view.leaveComposer()
          event.accepted = true
        }
      }
    }

    // What is being quoted, as it will appear under the commit.
    Rectangle {
      visible: !!root.view.quoting
      width: column.width
      height: quoted.implicitHeight + Style.space(14)
      color: "transparent"
      border.width: 1
      border.color: root.view.railColor
      radius: 0
      Mono {
        id: quoted
        x: Style.space(10)
        y: Style.space(7)
        width: parent.width - Style.space(20)
        textFormat: Text.StyledText
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
        text: root.view.quoting
          ? root.view.dimmed("❝ " + Model.rowFor(root.view.quoting).handle + " · esc drops the quote") + "<br>"
            + root.view.esc(Model.rowFor(root.view.quoting).body)
          : ""
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(12)
      Mono {
        anchors.verticalCenter: parent.verticalCenter
        text: root.remaining + "   ctrl+enter"
        color: root.remaining < 0 ? root.view.destructive : Color.muted
      }
      Rectangle {
        width: label.implicitWidth + Style.space(24)
        height: label.implicitHeight + Style.space(10)
        radius: 0
        color: root.view.primary
        opacity: root.ready ? 1 : 0.45
        Mono {
          id: label
          anchors.centerIn: parent
          text: root.view.quoting ? "Quote" : "Commit"
          color: Color.background
          font.bold: true
        }
        HoverHandler { cursorShape: root.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: root.view.postComposer() }
      }
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    x: root.railWidth
    width: root.width - x
    height: 1
    color: root.view.railColor
  }
}

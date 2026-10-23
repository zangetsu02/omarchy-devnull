import QtQuick
import qs.Commons
import "../ui"
import "../data/Model.js" as Model

// Where a profile stands, as the site shows it under the header: the commit
// activity graph in the owner's lane, the streaks, the level with its XP bar,
// and the achievements, unlocked ones first.
Column {
  id: root

  required property var view
  // The bridge's `standing` answer: { achievements, activity, streaks }.
  // (Not `data`: every Item already has a `data`, the list of its children.)
  property var standing: ({})
  property color lane: Color.accent

  readonly property var level: Model.standingFor(standing.achievements)
  readonly property var cells: Model.activityCells(standing.activity)
  readonly property bool yearly: !!standing.activity && standing.activity.scale === "year"
  readonly property var streaks: standing.streaks || {}
  readonly property real gap: 3

  visible: level.known
  spacing: Style.space(12)

  // --- Commit activity ------------------------------------------------------------

  Item {
    width: root.width
    height: activityTitle.implicitHeight
    Mono { id: activityTitle; text: "Commit activity"; font.pixelSize: Style.font.body; font.bold: true }
    Mono { anchors.right: parent.right; text: Model.activitySummary(root.standing.activity); color: Color.muted }
  }

  // A strip for a day, a week or a month; a week-per-column grid for a year.
  Grid {
    id: graph
    readonly property int columnsShown: root.yearly ? Math.ceil(root.cells.length / 7) : root.cells.length
    readonly property real cell: columnsShown > 0 ? (root.width - root.gap * (columnsShown - 1)) / columnsShown : 0
    rows: root.yearly ? 7 : 1
    flow: Grid.TopToBottom
    spacing: root.gap

    Repeater {
      model: root.cells
      Rectangle {
        required property var modelData
        width: graph.cell
        height: root.yearly ? graph.cell : Style.space(40)
        radius: 2
        // The lane mixed into the background by how busy the bucket was.
        color: modelData.level === 0
          ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          : Qt.rgba(root.lane.r, root.lane.g, root.lane.b, [0, 0.32, 0.56, 0.8, 1][modelData.level])
      }
    }
  }

  Row {
    visible: !root.yearly
    Repeater {
      model: root.cells
      Mono {
        required property var modelData
        width: graph.cell + root.gap
        text: modelData.label
        color: Color.muted
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignLeft
      }
    }
  }

  Item {
    width: root.width
    height: legend.implicitHeight
    Mono {
      visible: (root.streaks.longest || 0) > 0
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      text: Model.colored("longest streak ", Color.muted) + Model.escapeHtml(Model.plural(root.streaks.longest || 0, "day"))
        + ((root.streaks.current || 0) > 0
          ? Model.colored("  ·  ", Color.muted) + Model.colored("●", root.lane) + Model.colored(" current ", Color.muted) + root.streaks.current
          : "")
    }
    Row {
      id: legend
      anchors.right: parent.right
      spacing: 3
      Mono { text: "Less "; color: Color.muted; font.pixelSize: Style.font.caption }
      Repeater {
        model: [0, 1, 2, 3, 4]
        Rectangle {
          required property int modelData
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(9)
          height: width
          radius: 2
          color: modelData === 0
            ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            : Qt.rgba(root.lane.r, root.lane.g, root.lane.b, [0, 0.32, 0.56, 0.8, 1][modelData])
        }
      }
      Mono { text: " More"; color: Color.muted; font.pixelSize: Style.font.caption }
    }
  }

  Rectangle { width: root.width; height: 1; color: root.view.railColor }

  // --- Level ---------------------------------------------------------------------

  Item {
    width: root.width
    height: levelTitle.implicitHeight
    Mono {
      id: levelTitle
      textFormat: Text.StyledText
      font.pixelSize: Style.font.body
      text: Model.TROPHY + "  <b>" + Model.escapeHtml(root.level.label) + "</b>"
        + Model.colored("  ·  " + root.level.xp + " XP", Color.muted)
    }
    Mono {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.level.unlocked + " / " + root.level.badges.length + " unlocked"
      color: Color.muted
    }
  }

  Column {
    width: root.width
    spacing: Style.space(4)
    Item {
      width: root.width
      height: xpLeft.implicitHeight
      Mono { id: xpLeft; text: root.level.xp + " / " + root.level.nextXp + " XP"; color: Color.muted; font.pixelSize: Style.font.caption }
      Mono { anchors.right: parent.right; text: root.level.toNext; color: Color.muted; font.pixelSize: Style.font.caption }
    }
    Rectangle {
      width: root.width
      height: Style.space(6)
      radius: height / 2
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
      Rectangle {
        width: parent.width * root.level.progress
        height: parent.height
        radius: parent.radius
        color: root.lane
      }
    }
  }

  // Unlocked badges bright, the rest faint with how far along they are.
  Flow {
    width: root.width
    spacing: Style.space(6)
    Repeater {
      model: root.level.badges
      Rectangle {
        id: badge
        required property var modelData
        width: badgeRow.implicitWidth + Style.space(14)
        height: badgeRow.implicitHeight + Style.space(8)
        color: "transparent"
        border.width: 1
        border.color: modelData.unlocked ? Color.muted : root.view.railColor
        opacity: modelData.unlocked ? 1 : 0.55
        Row {
          id: badgeRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Mono { text: badge.modelData.glyph; color: badge.modelData.unlocked ? root.lane : Color.muted; font.pixelSize: Style.font.body }
          Mono { anchors.verticalCenter: parent.verticalCenter; text: badge.modelData.name || badge.modelData.id }
          Mono {
            visible: !badge.modelData.unlocked && (badge.modelData.target || 0) > 1
            anchors.verticalCenter: parent.verticalCenter
            text: (badge.modelData.progress || 0) + "/" + badge.modelData.target
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }
        // The description, under the pointer, as the site's dialog has it.
        HoverHandler { id: badgeHover }
        Tip { visible: badgeHover.hovered; text: badge.modelData.description || "" }
      }
    }
  }

  // A small tooltip above the badge; the shell's own tooltip needs a window anchor.
  component Tip: Rectangle {
    property alias text: tip.text
    z: 5
    y: -height - 4
    width: tip.implicitWidth + Style.space(12)
    height: tip.implicitHeight + Style.space(6)
    color: Color.background
    border.width: 1
    border.color: Color.muted
    Mono { id: tip; anchors.centerIn: parent }
  }
}

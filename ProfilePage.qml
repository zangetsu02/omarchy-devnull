import QtQuick
import QtQuick.Controls
import qs.Commons
import "Model.js" as Model

// Someone's profile, yours included: the header (avatar in its lane ring, bio,
// counts, Follow), then their commits, followers or following. The header is
// the list's own header, so the whole page scrolls as one.
Item {
  id: root

  required property var view
  required property var service
  property string username: ""

  property var user: ({})
  // Level, achievements and commit activity, from the bridge's `standing`.
  property var standing: ({})
  // "commits", "followers" or "following".
  property string tab: "commits"
  readonly property bool isMe: username !== "" && username === view.myUsername
  readonly property alias commitList: commitList
  readonly property color lane: view.laneColor(user.lane || 0)
  readonly property string handle: "@" + (user.username || username)

  onUsernameChanged: {
    root.user = ({ username: root.username })
    root.standing = ({})
    root.tab = "commits"
    if (root.username !== "") root.service.fetchStanding(root.username, function (answer) {
      if (root.user.username === root.username) root.standing = answer
    })
    if (root.username !== "") root.service.fetchUser(root.username, function (user) {
      // Another profile may have been opened while this one was on its way.
      if (user.username !== root.username) return
      root.user = user
      // The header grows once the profile lands (bio, counts), and a list does
      // not move its start for a header that changed size: back to the top.
      Qt.callLater(function () {
        commitList.positionViewAtBeginning()
        people.positionViewAtBeginning()
      })
    })
  }

  Pager {
    id: commitPager
    service: root.service
    args: root.username !== "" ? ["user-commits", root.username] : []
  }
  Pager {
    id: peoplePager
    service: root.service
    args: root.username !== "" && root.tab !== "commits" ? [root.tab, root.username] : []
  }
  Connections {
    target: root.service
    function onUserChanged(username, change) { if (username === root.username) root.user = change(root.user) }
  }

  CommitList {
    id: commitList
    anchors.fill: parent
    visible: root.tab === "commits"
    view: root.view
    commits: commitPager.items
    hasMore: commitPager.nextCursor !== ""
    endLine: Model.listEnd({ loading: commitPager.loading, error: commitPager.error, more: hasMore,
                             count: commitPager.items.length, empty: "fatal: " + root.handle + " has not committed yet" })
    onLoadMore: commitPager.more()
    header: Header {}
  }

  ListView {
    id: people
    anchors.fill: parent
    visible: root.tab !== "commits"
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    model: peoplePager.items
    header: Header {}
    delegate: PersonRow {}
    footer: Item {
      width: people.width
      height: Style.space(52)
      Mono {
        anchors.centerIn: parent
        color: Color.muted
        text: Model.listEnd({ loading: peoplePager.loading, error: peoplePager.error,
                              more: peoplePager.nextCursor !== "", count: peoplePager.items.length,
                              end: "That's everyone.", empty: "fatal: nobody here yet" })
      }
      TapHandler { onTapped: peoplePager.more() }
    }
  }

  // --- Building blocks ------------------------------------------------------------

  component Header: Column {
    width: ListView.view ? ListView.view.width : 0
    padding: Style.space(20)
    spacing: Style.space(10)

    Row {
      spacing: Style.space(16)
      Avatar {
        size: Style.space(64)
        ring: root.lane
        source: root.user.avatar_url || ""
        name: root.user.name || root.username
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Mono { text: root.user.name || root.username; font.pixelSize: Style.font.subtitle + 4; font.bold: true }
        Row {
          spacing: Style.space(8)
          Rectangle { width: Style.space(8); height: width; radius: width / 2; color: root.lane; anchors.verticalCenter: parent.verticalCenter }
          Mono { text: root.handle; color: Color.muted }
          // The level, tinted in the owner's lane, as the site prints it.
          Chip {
            visible: Model.standingFor(root.standing.achievements).known
            text: Model.standingFor(root.standing.achievements).label
            tint: root.lane
          }
          Chip { visible: root.user.follows_you === true; text: "follows you" }
        }
      }
    }

    Mono {
      visible: text !== ""
      width: parent.width - parent.padding * 2
      text: root.user.bio || ""
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    Mono {
      visible: text !== ""
      text: [root.user.location, root.user.company, root.user.website].filter(function (v) { return !!v }).join("  ·  ")
      color: Color.muted
    }

    Row {
      spacing: Style.space(10)
      ActionButton {
        visible: !root.isMe && root.user.is_followed !== undefined
        icon: root.user.is_followed ? Model.ICONS.following : Model.ICONS.follow
        label: root.user.is_followed ? "following" : "follow"
        active: !root.user.is_followed
        activeColor: root.view.primary
        border.width: 1
        border.color: root.user.is_followed ? root.view.railColor : root.view.primary
        onClicked: root.service.follow(root.username, !root.user.is_followed)
      }
      ActionButton { icon: "↗"; label: "on the site"; onClicked: root.view.openOnSite(root.user.html_url) }
    }

    Standing {
      width: parent.width - parent.padding * 2
      view: root.view
      standing: root.standing
      lane: root.lane
    }

    // The counts are the tabs: commits, followers, following.
    Row {
      spacing: Style.space(4)
      x: -Style.space(6)
      Repeater {
        model: [
          { key: "commits", count: root.user.commits_count },
          { key: "followers", count: root.user.followers_count },
          { key: "following", count: root.user.following_count }
        ]
        ActionButton {
          required property var modelData
          label: (modelData.count || 0) + " " + modelData.key
          active: root.tab === modelData.key
          activeColor: Color.foreground
          border.width: active ? 1 : 0
          border.color: root.view.primary
          onClicked: root.tab = modelData.key
        }
      }
    }

    Rectangle { width: parent.width - parent.padding * 2; height: 1; color: root.view.railColor }
  }

  component Chip: Rectangle {
    property alias text: chipText.text
    // Untinted, a quiet grey label; tinted, the colour carries it.
    property color tint: "transparent"
    readonly property bool tinted: tint.a > 0
    width: chipText.implicitWidth + Style.space(10)
    height: chipText.implicitHeight + Style.space(4)
    radius: Style.space(4)
    color: tinted ? Qt.rgba(tint.r, tint.g, tint.b, 0.14) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
    border.width: tinted ? 1 : 0
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.5)
    Mono { id: chipText; anchors.centerIn: parent; color: parent.tinted ? parent.tint : Color.muted; font.pixelSize: Style.font.caption }
  }

  component PersonRow: Item {
    id: person
    required property var modelData
    width: people.width
    height: Style.space(60)

    Rectangle {
      anchors.fill: parent
      visible: personHover.hovered
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
    }
    HoverHandler { id: personHover; cursorShape: Qt.PointingHandCursor }

    Avatar {
      id: face
      x: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      size: Style.space(36)
      ring: root.view.laneColor(person.modelData.lane || 0)
      source: person.modelData.avatar_url || ""
      name: person.modelData.name || person.modelData.username
    }
    Column {
      x: face.x + face.width + Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: person.width - x - followButton.width - Style.space(32)
      Mono {
        textFormat: Text.StyledText
        text: "<b>" + root.view.esc(person.modelData.name || person.modelData.username) + "</b>  "
          + root.view.dimmed("@" + person.modelData.username)
        font.pixelSize: Style.font.body
      }
      Mono { width: parent.width; text: person.modelData.bio || ""; color: Color.muted; elide: Text.ElideRight }
    }
    ActionButton {
      id: followButton
      visible: person.modelData.is_followed !== undefined && person.modelData.username !== root.view.myUsername
      anchors.right: parent.right
      anchors.rightMargin: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      label: person.modelData.is_followed ? "following" : "follow"
      active: !person.modelData.is_followed
      activeColor: root.view.primary
      onClicked: root.service.follow(person.modelData.username, !person.modelData.is_followed)
    }
    Rectangle { anchors.bottom: parent.bottom; x: face.x; width: person.width - x; height: 1; color: root.view.railColor }
    TapHandler { onTapped: root.view.openProfile(person.modelData.username) }
  }
}

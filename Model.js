.pragma library

// Everything the panel needs to turn what the bridge printed into what it draws.
// Pure functions only: no network, no filesystem, no QML — so node can check them.

// The manifest's own bounds, repeated here because the panel clamps whatever
// the settings hand it rather than trusting it.
var POLL_CLOSED = { fallback: 60, min: 30, max: 3600 }
var POLL_OPEN = { fallback: 20, min: 5, max: 120 }

var VERBS = {
    replied: "replied",
    mentioned: "mentioned you",
    quoted: "quoted",
    starred: "starred",
    followed: "followed you",
    approved: "approved your commit",
    rejected: "rejected your commit",
    leveled_up: "levelled you up"
}

// Action icons from the Nerd Font Omarchy ships as its monospace font: one
// font, one set of metrics, so they line up with the labels beside them.
// (☆ ↩ ⧉ came from different fallback fonts and sat at different heights.)
var ICONS = {
    star: "\u{f04ce}", unstarred: "\u{f04d2}", reply: "\u{f045a}", quote: "\u{f10d}",
    copy: "\u{f018f}", expand: "\u{f0142}", collapse: "\u{f0140}",
    follow: "\u{f0415}", following: "\u{f012c}"
}

// --- Small immutable helpers ----------------------------------------------------
//
// QML only redraws what it sees reassigned, so state is never edited in place:
// these return a copy with the change applied.

function merged(base, changes) {
    var copy = {}
    for (var key in (base || {})) copy[key] = base[key]
    for (var change in (changes || {})) copy[change] = changes[change]
    return copy
}

function without(base, dropped) {
    var copy = {}
    for (var key in (base || {})) if (key !== dropped) copy[key] = base[key]
    return copy
}

// Only web links leave the shell: a link from the server is opened with
// xdg-open, which would just as happily run any other scheme's handler.
function webUrl(url) {
    return /^https?:\/\//i.test(String(url || "")) ? String(url) : ""
}

// --- Commits ----------------------------------------------------------------------

function rowFor(commit) {
    var author = commit.author || {}
    return {
        id: commit.id,
        hash: commit.short_hash || "",
        handle: "@" + (author.username || "?"),
        body: commit.body || "",
        stars: commit.stars_count || 0,
        starred: commit.starred === true,
        replies: commit.replies_count || 0,
        pending: commit.status === "pending",
        url: commit.html_url || "",
        created: commit.created_at || "",
        name: author.name || author.username || "?",
        username: author.username || "",
        avatar: author.avatar_url || "",
        lane: laneOf(commit),
        deleted: !!commit.deleted_at,
        link: commit.link_preview && commit.link_preview.title ? {
            title: commit.link_preview.title,
            url: commit.link_preview.url || "",
            site: commit.link_preview.site_name || hostOf(commit.link_preview.url),
            image: webUrl(commit.link_preview.image_url)
        } : null,
        quoted: commit.quoted_commit && commit.quoted_commit.id ? rowFor(commit.quoted_commit) : null,
        images: imagesOf(commit),
        preview: ((commit.reply_preview || {}).data) || []
    }
}

// The pictures attached to a commit, with what the layout needs to size them
// before they load. Anything that is not a web URL is left out.
function imagesOf(commit) {
    return (commit.images || []).map(function (image) {
        return {
            url: webUrl(image.url),
            width: image.width > 0 ? image.width : 1,
            height: image.height > 0 ? image.height : 1,
            alt: image.description || ""
        }
    }).filter(function (image) { return image.url !== "" })
}

// How big one picture is drawn: as wide as the column allows, but never
// taller than `maxHeight`, keeping its proportions either way.
function fitImage(image, maxWidth, maxHeight) {
    var scale = Math.min(maxWidth / image.width, maxHeight / image.height, 1)
    return { width: Math.round(image.width * scale), height: Math.round(image.height * scale) }
}

function hostOf(url) {
    var match = String(url || "").match(/^[a-z]+:\/\/([^\/]+)/i)
    return match ? match[1].replace(/^www\./, "") : ""
}

// "now", "7m", "3h", "2d": the age the site prints next to a commit.
function ageFor(iso, nowMs) {
    var then = Date.parse(iso)
    if (isNaN(then)) return ""
    var minutes = Math.floor(Math.max(0, nowMs - then) / 60000)
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + "m"
    if (minutes < 1440) return Math.floor(minutes / 60) + "h"
    return Math.floor(minutes / 1440) + "d"
}

// One line for the popup: "@who verb: words".
function summaryFor(notification) {
    var notice = noticeFor(notification)
    var line = "@" + (notice.actor.username || "?") + " " + notice.verb
    return notice.body ? line + ": " + notice.body : line
}

function badgeFor(count, broken) {
    if (broken) return { text: "!", state: "broken" }
    if (!count) return { text: "", state: "quiet" }
    return { text: count > 99 ? "99+" : String(count), state: "unread" }
}

function pollDelay(panelOpen, settings) {
    var bounds = panelOpen ? POLL_OPEN : POLL_CLOSED
    var name = panelOpen ? "openRefreshIntervalSec" : "refreshIntervalSec"
    var seconds = (settings || {})[name]
    if (typeof seconds !== "number" || isNaN(seconds)) seconds = bounds.fallback
    seconds = Math.max(bounds.min, Math.min(bounds.max, seconds))
    return seconds * 1000
}

// How many auth failures in a row before the icon admits the pairing is gone.
// A revoked device never recovers, so the panel has to say so; a flaky network
// does, so it must not count.
var BROKEN_AFTER = 3

function tickCalls(panelOpen, broken, expanded) {
    if (broken) return []
    // Closed, only /me: it carries the unread count without marking anything read.
    if (!panelOpen) return ["me"]
    // Once older pages are loaded, refreshing would replace everything scrolled
    // to with page one. The feed waits until the panel is opened again.
    return expanded ? [] : ["feed"]
}

function openCalls(broken) {
    // Broken, one probe: it costs nothing and it is how a re-pair gets noticed
    // without restarting the shell.
    if (broken) return ["me"]
    // The one place notifications are listed, which is also what marks them read.
    return ["notifications", "feed"]
}

// --- Reply drafts ------------------------------------------------------------
//
// Held per commit id, not per row: the feed is replaced wholesale on every
// refresh, so a delegate — and the field inside it — can go away mid-sentence.

function keepsDraft(answer) {
    return !!(answer && answer.error)
}

function draftFor(drafts, id) {
    if (!drafts) return ""
    return drafts[id] || ""
}

function withDraft(drafts, id, text) {
    var change = {}
    change[id] = text
    return merged(drafts, change)
}

function clearDraft(drafts, id) {
    return without(drafts, id)
}

function nextFailureCount(count, result) {
    if (!result) return 0
    if (result.kind === "auth") return count + 1
    return count
}

function isBroken(count) {
    return count >= BROKEN_AFTER
}

function errorLine(result) {
    if (!result) return ""
    switch (result.kind) {
    case "expired":
        return "dev-null refused the signature. Check this machine's clock."
    case "auth":
        return "This machine is not paired any more. Run scripts/setup-devnull."
    case "rules":
        return "Accept the commit rules on dev-null.sh once, then try again."
    case "limited":
        return "Too many requests for now. It will catch up by itself."
    case "network":
        return "dev-null is out of reach."
    default:
        return result.error || "Something went wrong."
    }
}

function withStar(commit, starred) {
    if (starred === commit.starred) return commit
    var count = commit.stars_count || 0
    // Every other field rides along: a thread preview or a link card must not
    // vanish because someone pressed s.
    return merged(commit, { starred: starred, stars_count: starred ? count + 1 : Math.max(0, count - 1) })
}

function withFollow(user, followed) {
    if (followed === user.is_followed) return user
    var count = user.followers_count || 0
    return merged(user, { is_followed: followed, followers_count: followed ? count + 1 : Math.max(0, count - 1) })
}

// --- The log -----------------------------------------------------------------

// dev-null's own colours, from its DESIGN.md: six author lanes (burnt orange,
// green, violet, teal, rose, ochre), one blue for "you can act here", one red
// for deleting. The theme still gives background, text and font; it picks the
// dark or light set by how light its background is.
var PALETTE = {
    dark: {
        lanes: ["#ff8a4c", "#51cf66", "#da77f2", "#3bc9db", "#f06595", "#fcc419"],
        primary: "#7aa2f7",
        destructive: "#ff6b6b"
    },
    light: {
        lanes: ["#d9480f", "#2f9e44", "#9c36b5", "#0c8599", "#c2255c", "#b7791f"],
        primary: "#3b6fe0",
        destructive: "#c92a2a"
    }
}

function paletteFor(backgroundLightness) {
    return backgroundLightness > 0.5 ? PALETTE.light : PALETTE.dark
}

function laneOf(commit) {
    var lane = ((commit && commit.author) || {}).lane
    return typeof lane === "number" && lane >= 0 && lane < PALETTE.dark.lanes.length ? lane : 0
}

// The commit with this id, wherever it sits: on the log, or in a reply preview
// under it. Only the path to it is copied, so QML redraws only what changed.
function mapCommit(list, id, change) {
    var out = list
    for (var i = 0; i < (list || []).length; i++) {
        var commit = list[i]
        var next = commit
        if (commit.id === id) next = change(commit)
        else if (commit.reply_preview && commit.reply_preview.data && commit.reply_preview.data.length) {
            var inner = mapCommit(commit.reply_preview.data, id, change)
            if (inner !== commit.reply_preview.data)
                next = merged(commit, { reply_preview: merged(commit.reply_preview, { data: inner }) })
        }
        if (next !== commit) {
            if (out === list) out = list.slice()
            out[i] = next
        }
    }
    return out
}

// What the composer may still take; the site's limit, counted the same way.
var BODY_LIMIT = 4000

function charsLeft(text) {
    return BODY_LIMIT - String(text || "").length
}

// "1 reply", "3 replies": the count and the noun the site would print.
function plural(count, one, many) {
    return count + " " + (count === 1 ? one : (many || one + "s"))
}

// --- Notifications -------------------------------------------------------------

var NOTICE_ICONS = {
    replied: "↩", mentioned: "@", quoted: "❝", starred: "★",
    followed: "+", approved: "✓", rejected: "✗", leveled_up: "⇡"
}
// The colour of a notice's icon: a lane index, or one of the palette's roles.
// Replies are blue because they ask you to act; a rejection is red.
var NOTICE_TINTS = {
    replied: "primary", rejected: "destructive",
    starred: 5, quoted: 2, mentioned: 3, followed: 1, approved: 1, leveled_up: 0
}

function noticeTint(type, palette) {
    var tint = NOTICE_TINTS[type]
    if (typeof tint === "number") return palette.lanes[tint]
    return tint ? palette[tint] : ""
}

// Whose words the commit under a notice are: theirs (a reply, a mention, a
// quote) or yours (what they starred, what moderation decided on).
var THEIR_WORDS = { replied: true, mentioned: true, quoted: true }

function noticeFor(notification) {
    var actors = notification.actors && notification.actors.length ? notification.actors : [notification.actor || {}]
    var first = actors[0] || {}
    var commit = notification.commit || {}
    return {
        icon: NOTICE_ICONS[notification.type] || "•",
        type: notification.type,
        actor: first,
        others: actors.length - 1,
        verb: VERBS[notification.type] || notification.type,
        theirs: THEIR_WORDS[notification.type] === true,
        body: commit.body || "",
        reason: notification.reason || "",
        created: notification.created_at || "",
        unread: !notification.read_at,
        url: commit.html_url || first.html_url || ""
    }
}

// The last line of any list, in git's voice: still loading, what went wrong,
// that there is more, that this is the end, or that there is nothing at all.
function listEnd(state) {
    if (state.loading) return "loading…"
    if (state.error) return "fatal: " + state.error
    if (state.more) return "older…"
    if (state.count > 0) return state.end || "That's the root commit. There's nothing before it."
    return state.empty || "fatal: nothing here yet"
}

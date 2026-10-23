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
    leveled_up: "levelled up"
}

// Action icons from the Nerd Font Omarchy ships as its monospace font: one
// font, one set of metrics, so they line up with the labels beside them.
// (☆ ↩ ⧉ came from different fallback fonts and sat at different heights.)
var ICONS = {
    star: "\u{f04ce}", unstarred: "\u{f04d2}", reply: "\u{f045a}", quote: "\u{f10d}",
    copy: "\u{f018f}", expand: "\u{f0142}", collapse: "\u{f0140}",
    follow: "\u{f0415}", following: "\u{f012c}",
    mute: "\u{f075f}", block: "\u{f0159}", pastel: "\u{f0e0e}"
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

// For labels in Text.StyledText: what came from the server is escaped, then
// wrapped in a colour when one is given.
function escapeHtml(text) {
    return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function colored(text, color) {
    return "<font color='" + color + "'>" + escapeHtml(text) + "</font>"
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
        pasteis: commit.pasteis_count || 0,
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
    if (notice.aboutYou) return "You " + notice.verb
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

// What to call on a tick, given where the panel stands. The state arrives as
// one named object rather than a row of booleans, so a call site reads as a
// sentence instead of `tickCalls(a, b, c, d)`.
//
// state: { panelOpen, broken, expanded, signedOut }
function tickCalls(state) {
    var s = state || {}
    // Never paired: the home page carries the whole Latest log as JSON, with no
    // signature, so the panel shows the real thing instead of an empty screen.
    if (s.signedOut) return ["publicFeed"]
    if (s.broken) return []
    // Closed, only /me: it carries the unread count without marking anything read.
    if (!s.panelOpen) return ["me"]
    // Once older pages are loaded, refreshing would replace everything scrolled
    // to with page one. The feed waits until the panel is opened again.
    return s.expanded ? [] : ["feed"]
}

function openCalls(state) {
    var s = state || {}
    if (s.signedOut) return ["publicFeed"]
    // Broken, one probe: it costs nothing and it is how a re-pair gets noticed
    // without restarting the shell.
    if (s.broken) return ["me"]
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

// Drafts outlive the shell. What goes to disk is only what someone typed and
// has not sent: ids mapped to text, nothing else, and nothing empty.
function draftsToJson(drafts) {
    var out = {}
    for (var id in (drafts || {})) {
        var text = drafts[id]
        if (typeof text === "string" && text !== "") out[id] = text
    }
    return JSON.stringify(out)
}

function draftsFromJson(text) {
    var parsed = {}
    try { parsed = JSON.parse(text || "{}") || {} } catch (e) { return {} }
    if (typeof parsed !== "object" || parsed === null) return {}
    var out = {}
    // The file is ours, but it is still a file: anything that is not text
    // keyed by an id is dropped rather than handed to a view.
    for (var id in parsed) if (typeof parsed[id] === "string") out[id] = parsed[id]
    return out
}

function clearDraft(drafts, id) {
    return without(drafts, id)
}

function nextFailureCount(count, result) {
    if (!result) return 0
    // Only a device the server refuses counts. Never having paired is not a
    // failure, and neither is a wrong clock or a dead network.
    if (result.kind === "auth") return count + 1
    return count
}

function isBroken(count) {
    return count >= BROKEN_AFTER
}

function errorLine(result) {
    if (!result) return ""
    switch (result.kind) {
    case "unpaired":
        // Not an error: this machine has simply never been connected. The panel
        // offers the connection itself; a red line would only be in the way.
        return ""
    case "expired":
        return "dev-null refused the signature. Check this machine's clock."
    case "auth":
        return "This machine is not paired any more. Run scripts/setup-devnull."
    case "rules":
        return "Accept the commit rules on dev-null.sh once, then try again."
    case "exhausted":
        return "That was your last pastel for today. More tomorrow."
    case "limited":
        return "Too many requests for now. It will catch up by itself."
    case "network":
        return "dev-null is out of reach."
    default:
        return result.error || "Something went wrong."
    }
}

// What the panel says after giving a pastel. The count is the whole message:
// nobody needs to be told what they just did, only what is left.
// Whether a list of accounts holds this handle, so a button can offer to lift
// what it set. dev-null compares handles without case, so this does too.
function silences(users, username) {
    if (!username) return false
    var wanted = String(username).toLowerCase()
    for (var i = 0; i < (users || []).length; i++)
        if (String((users[i] || {}).username || "").toLowerCase() === wanted) return true
    return false
}

function pasteisLine(left) {
    if (left < 0) return "Pastel given."
    if (left === 0) return "That was your last pastel for today."
    return "Pastel given. " + plural(left, "pastel", "pastéis") + " left today."
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
        // A level-up has no one else in it: its "actor" is you.
        aboutYou: notification.type === "leveled_up",
        theirs: THEIR_WORDS[notification.type] === true,
        body: commit.body || "",
        reason: notification.reason || "",
        created: notification.created_at || "",
        unread: !notification.read_at,
        commitId: commit.id || ""
    }
}

// Where a click on a notice goes when it does not land on a name or a commit:
// a follow to the follower, a level-up to your own profile, anything else to
// the commit it is about. { page, argument }, or null when there is nowhere.
function noticeTarget(notice, myUsername) {
    if (notice.type === "followed") return { page: "profile", argument: notice.actor.username || "" }
    if (notice.type === "leveled_up") return { page: "profile", argument: myUsername }
    if (notice.commitId) return { page: "commit", argument: notice.commitId }
    return null
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

// --- Standing: level, achievements, commit activity ----------------------------

// The site's Lucide icons, as the same drawings in the Nerd Font.
var BADGE_ICONS = {
    "terminal": "\u{f018d}", "file-code": "\u{f022e}", "flame": "\u{f0238}", "zap": "\u{f140b}",
    "server": "\u{f048b}", "box": "\u{f03d6}", "shield": "\u{f0498}", "star": "\u{f04ce}",
    "sparkles": "\u{f0674}", "git-merge": "\u{f062d}", "key": "\u{f0306}", "cookie": "\u{f0198}",
    "bot-off": "\u{f06a9}", "bomb": "\u{f0691}"
}
var TROPHY = "\u{f0538}"

// Where a profile stands: "Lv. 3 · operator", how far into the level it is,
// what the next rank is, and its badges with the unlocked ones first.
function standingFor(achievements) {
    var a = achievements || {}
    var ranks = a.ranks || []
    var next = ranks.filter(function (r) { return !r.achieved })[0] || null
    var badges = (a.badges || []).map(function (badge) {
        return merged(badge, { glyph: BADGE_ICONS[badge.icon] || "•" })
    })
    var unlocked = badges.filter(function (b) { return b.unlocked })
    return {
        known: typeof a.level === "number",
        label: "Lv. " + (a.level || 0) + " · " + (a.rank || "?"),
        xp: a.xp || 0,
        nextXp: a.next_level_xp || 0,
        progress: Math.max(0, Math.min(1, (a.level_progress || 0) / 100)),
        toNext: next ? Math.max(0, (a.next_level_xp || 0) - (a.xp || 0)) + " XP to " + next.rank : "top rank",
        badges: unlocked.concat(badges.filter(function (b) { return !b.unlocked })),
        unlocked: unlocked.length
    }
}

var WINDOWS = { day: "the last 24 hours", week: "the last 7 days", month: "the last 30 days", year: "the last year" }
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Each bucket of the activity graph, with how full it looks (0 empty, 1 to 4
// relative to the busiest bucket, as the site draws it) and its label, if any:
// every six hours for a day, every day for a week, Mondays for a month.
function activityCells(activity) {
    var buckets = (activity && activity.buckets) || []
    var scale = (activity && activity.scale) || "day"
    var busiest = buckets.reduce(function (most, b) { return Math.max(most, b.count || 0) }, 0)
    return buckets.map(function (bucket) {
        var count = bucket.count || 0
        var when = new Date(bucket.date)
        return {
            count: count,
            level: count === 0 || busiest === 0 ? 0 : Math.max(1, Math.ceil(count / busiest * 4)),
            label: activityLabel(when, scale)
        }
    })
}

function activityLabel(when, scale) {
    if (isNaN(when.getTime())) return ""
    if (scale === "day") return when.getHours() % 6 === 0 ? pad2(when.getHours()) + ":00" : ""
    if (scale === "week") return WEEKDAYS[when.getDay()] + " " + when.getDate()
    if (scale === "month") return when.getDay() === 1 ? MONTHS[when.getMonth()] + " " + when.getDate() : ""
    return ""
}

function pad2(n) { return n < 10 ? "0" + n : String(n) }

// "9 commits in the last 24 hours", or the site's line for an empty graph.
function activitySummary(activity) {
    var total = ((activity && activity.buckets) || []).reduce(function (sum, b) { return sum + (b.count || 0) }, 0)
    if (total === 0) return "No commits yet"
    return plural(total, "commit") + " in " + (WINDOWS[(activity && activity.scale) || "day"] || WINDOWS.day)
}

// --- The character grid ------------------------------------------------------
//
// The log is drawn as a terminal would draw it, so the rail is characters
// rather than rectangles. Every glyph here is one column wide: a two-cell one
// would shear every line beneath it.

// Every glyph the grid draws, in one place, so tests/glyph-test can ask
// fontconfig who serves each one. A glyph the monospace font lacks falls back
// to another face at another width and shears every line under it — which is
// why the counters are Nerd Font private-use points and not ★ ☆ ⤷.
var GLYPHS = {
    node: "○", nodeHere: "●", nodeGone: "◌",
    bar: "│", dottedBar: "┆", branch: "├", lastBranch: "╰", dash: "─", arm: "╴",
    topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
    star: "\u{f04ce}", unstarred: "\u{f04d2}", replies: "\u{f045a}",
    cursorBar: "▌", ellipsis: "…"
}

// One marker, not two. Filled is the cursor, the way LazyVim keeps `cursorline`
// as the only mark and lets the mouse move it rather than add a state.
function nodeGlyph(commit, selected) {
    if (commit && commit.deleted_at) return GLYPHS.nodeGone   // a tombstone keeps its place
    return selected ? GLYPHS.nodeHere : GLYPHS.node
}

function rail(kind, opts) {
    var o = opts || {}
    switch (kind) {
    case "body": return GLYPHS.bar
    // The staged commit's lane is dotted until there is something to commit.
    case "staged": return o.ready ? GLYPHS.bar : GLYPHS.dottedBar
    case "reply": return (o.last ? GLYPHS.lastBranch : GLYPHS.branch) + GLYPHS.dash + GLYPHS.arm
    default: return " "
    }
}

function _cut(text, room) {
    var chars = Array.from(String(text || ""))
    if (chars.length <= room) return chars.join("")
    if (room <= 1) return chars.slice(0, Math.max(0, room)).join("")
    return chars.slice(0, room - 1).join("") + GLYPHS.ellipsis
}

// A row's header, in two pieces, because QML anchors better than this can pad.
//
// It used to be one string padded to a column count. That was a lie: glyph
// positions round to whole pixels, so the line painted wider than the column it
// was padded to and Qt elided the counts off the end. Anchoring the right piece
// costs nothing and cannot drift.

function headerLeft(commit) {
    if (!commit) return ""
    var author = commit.author || {}
    return (commit.short_hash || "") + "  @" + (author.username || "?")
}

function headerRight(commit, nowMs) {
    if (!commit) return ""
    var parts = [ageFor(commit.created_at, nowMs === undefined ? Date.now() : nowMs)]
    if (commit.status === "pending") parts.push("held")
    if (commit.stars_count > 0)
        parts.push((commit.starred ? GLYPHS.star : GLYPHS.unstarred) + " " + commit.stars_count)
    if (commit.replies_count > 0) parts.push(GLYPHS.replies + " " + commit.replies_count)
    return parts.filter(function (part) { return !!part }).join("   ")
}

// A frame's top or bottom border, filling its width exactly. The title sits in
// the top border, the way a box-drawn pane labels itself.
function frameLine(kind, width, title) {
    if (!isFinite(width)) return ""
    var w = Math.floor(width)
    if (w < 2) return ""
    var corners = kind === "bottom" ? [GLYPHS.bottomLeft, GLYPHS.bottomRight]
                                    : [GLYPHS.topLeft, GLYPHS.topRight]
    var inner = w - 2
    var label = ""
    if (kind !== "bottom" && title) {
        // "─ title ─" needs two spaces and at least one dash on each side.
        var room = inner - 4
        if (room >= 1) label = " " + _cut(title, room) + " "
    }
    var dashes = inner - Array.from(label).length
    var lead = label ? 1 : 0
    return corners[0]
        + new Array(lead + 1).join(GLYPHS.dash)
        + label
        + new Array(Math.max(0, dashes - lead) + 1).join(GLYPHS.dash)
        + corners[1]
}

// --- Going somewhere by typing it --------------------------------------------
//
// dev-null's search is a web route behind a session cookie, and a client that
// signs its requests with a device key does not have one. What it can do
// without a server is resolve what someone typed.

var SITE = "dev-null.sh"

function destinationFor(text) {
    var typed = String(text || "").trim().replace(/\/+$/, "")
    if (typed === "") return null

    var link = typed.match(/^https?:\/\/([^/]+)\/@([A-Za-z0-9_-]+)(?:\/commits\/([A-Za-z0-9]+))?$/)
    if (link) {
        if (link[1] !== SITE) return null
        return link[3] ? { page: "commit", argument: link[3] }
                       : { page: "profile", argument: link[2] }
    }
    if (typed.indexOf("://") >= 0) return null

    if (typed.charAt(0) === "@")
        return { page: "profile", argument: typed.slice(1) }
    // Seven hex characters is a short hash; anything else that looks like a
    // handle is one.
    if (/^[0-9a-f]{7}$/.test(typed)) return { page: "commit", argument: typed }
    if (/^[A-Za-z0-9_-]+$/.test(typed)) return { page: "profile", argument: typed }
    return null
}

// --- Completing an @mention --------------------------------------------------
//
// From the handles already on screen, because there is no suggestion endpoint
// on the signed API either.

function _mentionWord(text) {
    var typed = String(text || "")
    var word = typed.slice(typed.lastIndexOf(" ") + 1)
    return word.charAt(0) === "@" ? word.slice(1) : null
}

function mentionsFor(text, handles) {
    var prefix = _mentionWord(text)
    if (prefix === null) return []
    var wanted = prefix.toLowerCase()
    var out = []
    for (var i = 0; i < (handles || []).length; i++) {
        var handle = handles[i]
        if (String(handle).toLowerCase().indexOf(wanted) === 0) out.push(handle)
    }
    return out
}

function completeMention(text, handle) {
    if (_mentionWord(text) === null) return text
    var typed = String(text)
    return typed.slice(0, typed.lastIndexOf("@")) + "@" + handle + " "
}

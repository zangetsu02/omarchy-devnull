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

function wrap(line, width) {
    var out = []
    var current = ""
    var words = line.split(/\s+/).filter(function (w) { return w.length > 0 })
    for (var i = 0; i < words.length; i++) {
        var word = words[i]
        // A word longer than the line gets broken, or it would never fit at all.
        while (word.length > width) {
            if (current.length > 0) { out.push(current); current = "" }
            out.push(word.slice(0, width))
            word = word.slice(width)
        }
        var candidate = current.length === 0 ? word : current + " " + word
        if (candidate.length <= width) {
            current = candidate
        } else {
            out.push(current)
            current = word
        }
    }
    if (current.length > 0) out.push(current)
    return out
}

function clampBody(text, lines, width) {
    if (!text) return ""
    var wrapped = []
    // Blank lines the author typed must not spend a line on nothing.
    var sourceLines = text.split("\n")
    for (var i = 0; i < sourceLines.length; i++) {
        var piece = wrap(sourceLines[i], width)
        for (var j = 0; j < piece.length; j++) wrapped.push(piece[j])
    }
    if (wrapped.length <= lines) return wrapped.join("\n")
    var kept = wrapped.slice(0, lines)
    kept[lines - 1] = kept[lines - 1] + "…"
    return kept.join("\n")
}

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
        url: commit.html_url || ""
    }
}

function summaryFor(notification) {
    var verb = VERBS[notification.type] || notification.type
    var actor = notification.actor || {}
    var who = "@" + (actor.username || "?")
    var commit = notification.commit || {}
    if (!commit.body) return who + " " + verb
    return who + " " + verb + ": " + commit.body
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

function tickCalls(panelOpen, broken) {
    if (broken) return []
    // Closed, only /me: it carries the unread count without marking anything read.
    return panelOpen ? ["feed"] : ["me"]
}

function openCalls() {
    // The one place notifications are listed, which is also what marks them read.
    return ["notifications", "feed"]
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
    var count = commit.stars_count || 0
    if (starred === commit.starred) return commit
    count = starred ? count + 1 : Math.max(0, count - 1)
    return {
        id: commit.id,
        short_hash: commit.short_hash,
        body: commit.body,
        author: commit.author,
        stars_count: count,
        starred: starred,
        replies_count: commit.replies_count,
        status: commit.status,
        html_url: commit.html_url
    }
}

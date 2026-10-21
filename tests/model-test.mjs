// Run with: node tests/model-test.mjs
// Model.js is a QML .pragma library, so it is loaded as plain source here.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import vm from "node:vm"

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "..", "Model.js"), "utf8").replace(".pragma library", "")
const Model = {}
vm.createContext(Model)
vm.runInContext(source, Model)

// Review Focus: an empty body still gives a row worth drawing.
const bare = Model.rowFor({
  id: "u", short_hash: "d453634", body: "",
  author: { username: "zangetsu02" }, stars_count: 0, starred: false,
  html_url: "https://dev-null.sh/x", status: "approved",
})
assert.equal(bare.hash, "d453634")
assert.equal(bare.handle, "@zangetsu02")
assert.equal(bare.body, "")
assert.ok(bare.url.length > 0)

// A row carries what the panel draws, and nothing it has to look up again.
const row = Model.rowFor({
  id: "u", short_hash: "36795c7", body: "a very long line that will not fit at all",
  author: { username: "ndk98z" }, stars_count: 12, starred: true,
  html_url: "https://dev-null.sh/y", status: "pending",
})
assert.equal(row.stars, 12)
assert.equal(row.starred, true)
assert.equal(row.pending, true)
assert.equal(bare.pending, false)

// An author the server did not send does not crash the row.
assert.equal(Model.rowFor({ id: "z", short_hash: "0000000" }).handle, "@?")

// A notification reads as one line: who, what, and enough to recognise it.
assert.equal(
  Model.summaryFor({ type: "replied", actor: { username: "pptx704" },
                     commit: { body: "Seems like github pages tho" } }),
  "@pptx704 replied: Seems like github pages tho")
assert.equal(
  Model.summaryFor({ type: "starred", actor: { username: "techenby" },
                     commit: { body: "I built chorei" } }),
  "@techenby starred: I built chorei")
assert.ok(Model.summaryFor({ type: "leveled_up", actor: null, commit: null }).length > 0)

// The badge: dark at zero, a count up to 99, then 99+, and broken wins.
// (Compared field by field: Model.js runs in its own vm context, so its objects
//  never match a literal by prototype.)
const quiet = Model.badgeFor(0, false)
assert.equal(quiet.text, "")
assert.equal(quiet.state, "quiet")
const seven = Model.badgeFor(7, false)
assert.equal(seven.text, "7")
assert.equal(seven.state, "unread")
assert.equal(Model.badgeFor(250, false).text, "99+")
assert.equal(Model.badgeFor(3, true).state, "broken")
assert.equal(Model.badgeFor(0, true).state, "broken")

// Closed polls slowly, open polls fast, and the settings are honoured.
assert.equal(Model.pollDelay(false, { refreshIntervalSec: 60 }), 60000)
assert.equal(Model.pollDelay(true, { openRefreshIntervalSec: 20 }), 20000)
// Missing settings fall back to the manifest's defaults rather than to zero.
assert.equal(Model.pollDelay(false, {}), 60000)
assert.equal(Model.pollDelay(true, {}), 20000)
// A value below the manifest's floor is clamped, not obeyed.
assert.equal(Model.pollDelay(false, { refreshIntervalSec: 1 }), 30000)

// The age next to a commit, as the site prints it.
const t0 = Date.parse("2026-10-21T07:00:00Z")
assert.equal(Model.ageFor("2026-10-21T07:00:00Z", t0 + 30000), "now")
assert.equal(Model.ageFor("2026-10-21T07:00:00Z", t0 + 7 * 60000), "7m")
assert.equal(Model.ageFor("2026-10-21T07:00:00Z", t0 + 3 * 3600000), "3h")
assert.equal(Model.ageFor("2026-10-21T07:00:00Z", t0 + 50 * 3600000), "2d")
assert.equal(Model.ageFor("", t0), "")
// A star must not lose the date, or the row forgets how old it is.
assert.equal(Model.withStar({ starred: false, created_at: "x" }, true).created_at, "x")

console.log("Model.js: all checks passed")

// The lanes are dev-null's, dark or light by the theme's background.
assert.equal(Model.paletteFor(0.05).lanes[0], "#ff8a4c")
assert.equal(Model.paletteFor(0.95).primary, "#3b6fe0")
assert.equal(Model.paletteFor(0.05).lanes.length, 6)
assert.equal(Model.laneOf({ author: { lane: 4 } }), 4)
assert.equal(Model.laneOf({ author: { lane: 9 } }), 0)

// A star keeps everything else the commit carried.
const rich = { id: "a", starred: false, stars_count: 1, reply_preview: { data: [] }, link_preview: { title: "t" } }
const starred = Model.withStar(rich, true)
assert.equal(starred.stars_count, 2)
assert.equal(starred.link_preview.title, "t")
assert.equal(rich.starred, false)

// A reply inside a preview is found and changed; untouched rows stay the same objects.
const log = [
  { id: "a", reply_preview: { data: [{ id: "a1", starred: false, stars_count: 0 }], next_cursor: null } },
  { id: "b" },
]
const changed = Model.mapCommit(log, "a1", (c) => Model.withStar(c, true))
assert.equal(changed[0].reply_preview.data[0].starred, true)
assert.equal(changed[1], log[1])
assert.equal(log[0].reply_preview.data[0].starred, false)
assert.equal(Model.mapCommit(log, "zz", (c) => c), log)

// The row carries what the log draws: lane, quote, link card, thread preview.
const logRow = Model.rowFor({
  id: "q", author: { username: "u", name: "U", lane: 2 },
  link_preview: { title: "Bref", url: "https://www.bref.sh/news" },
  quoted_commit: { id: "o", short_hash: "abc1234", author: { username: "o" }, body: "orig" },
  reply_preview: { data: [{ id: "r" }] },
})
assert.equal(logRow.lane, 2)
assert.equal(logRow.link.site, "bref.sh")
assert.equal(logRow.quoted.hash, "abc1234")
assert.equal(logRow.preview.length, 1)
assert.equal(Model.charsLeft("abc"), 3997)

console.log("Model.js: log checks passed")
assert.equal(Model.plural(1, "reply", "replies"), "1 reply")
assert.equal(Model.plural(3, "image"), "3 images")

// A grouped star: the first actor, how many others, and the words are yours.
const notice = Model.noticeFor({
  type: "starred", read_at: null, created_at: "2026-10-21T07:00:00Z",
  actors: [{ username: "a" }, { username: "b" }, { username: "c" }],
  commit: { body: "mine", html_url: "https://dev-null.sh/x" },
})
assert.equal(notice.actor.username, "a")
assert.equal(notice.others, 2)
assert.equal(notice.theirs, false)
assert.equal(notice.unread, true)
assert.equal(notice.icon, "★")
// A reply carries their words; an old notice without actors still has one.
const replied = Model.noticeFor({ type: "replied", actor: { username: "p" }, read_at: "x" })
assert.equal(replied.theirs, true)
assert.equal(replied.actor.username, "p")
assert.equal(replied.others, 0)
assert.equal(Model.listEnd({ loading: true }), "loading…")
assert.equal(Model.listEnd({ error: "offline", more: true }), "fatal: offline")
assert.equal(Model.listEnd({ more: true, count: 3 }), "older…")
assert.equal(Model.listEnd({ count: 3 }), "That's the root commit. There's nothing before it.")
assert.equal(Model.listEnd({ count: 0, empty: "fatal: no stars" }), "fatal: no stars")

// Only http(s) leaves the shell through xdg-open.
assert.equal(Model.webUrl("https://dev-null.sh/x"), "https://dev-null.sh/x")
assert.equal(Model.webUrl("file:///etc/passwd"), "")
assert.equal(Model.webUrl("javascript:alert(1)"), "")
assert.equal(Model.webUrl(undefined), "")

// Copies, never edits: the original stays as it was.
const base = { a: 1, b: 2 }
assert.deepEqual({ ...Model.merged(base, { b: 3 }) }, { a: 1, b: 3 })
assert.deepEqual({ ...Model.without(base, "a") }, { b: 2 })
assert.deepEqual(base, { a: 1, b: 2 })

// A follow moves the count with it, and never below zero.
assert.equal(Model.withFollow({ is_followed: false, followers_count: 2 }, true).followers_count, 3)
assert.equal(Model.withFollow({ is_followed: true, followers_count: 0 }, false).followers_count, 0)

// Notice icons take a lane or a role from the palette.
const dark = Model.paletteFor(0)
assert.equal(Model.noticeTint("replied", dark), dark.primary)
assert.equal(Model.noticeTint("starred", dark), dark.lanes[5])
assert.equal(Model.noticeTint("unknown", dark), "")

// Images keep their size for the layout; a non-web URL is dropped.
const pictured = Model.rowFor({
  id: "i", author: { username: "u" },
  images: [
    { url: "https://dev-null.sh/commit-images/a", width: 800, height: 400, description: "a chart" },
    { url: "file:///etc/passwd", width: 10, height: 10 },
  ],
  link_preview: { title: "t", url: "https://x.dev", image_url: "https://x.dev/card.png" },
})
assert.equal(pictured.images.length, 1)
assert.equal(pictured.images[0].alt, "a chart")
assert.equal(pictured.link.image, "https://x.dev/card.png")
assert.equal(Model.rowFor({ id: "n" }).images.length, 0)

// A wide picture fills the width; a tall one is capped by height; none grows.
assert.deepEqual({ ...Model.fitImage({ width: 800, height: 400 }, 400, 300) }, { width: 400, height: 200 })
assert.deepEqual({ ...Model.fitImage({ width: 900, height: 1600 }, 400, 320) }, { width: 180, height: 320 })
assert.deepEqual({ ...Model.fitImage({ width: 100, height: 50 }, 400, 300) }, { width: 100, height: 50 })
// Every action icon is one Nerd Font glyph from a private use area.
for (const glyph of Object.values(Model.ICONS)) assert.ok(glyph.codePointAt(0) >= 0xe000, glyph)

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

// Two lines and an ellipsis, never a broken word in the middle.
assert.equal(Model.clampBody("alpha beta gamma delta", 2, 11), "alpha beta\ngamma delta")
assert.equal(Model.clampBody("a".repeat(400), 2, 20).split("\n").length, 2)
assert.ok(Model.clampBody("x ".repeat(300), 2, 20).endsWith("…"))
// Short enough to fit is left exactly as it was.
assert.equal(Model.clampBody("ship it", 2, 20), "ship it")
// Newlines the author typed do not get to spend both lines on nothing.
assert.equal(Model.clampBody("one\n\n\ntwo", 2, 20), "one\ntwo")

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

// Lanes come from the theme, in dev-null's order, with a fallback for gaps.
const toml = 'orange = "#ff8800"\ngreen = "#00ff00"\nmagenta="#ff00ff"\ncyan = "#00ffff"\nred = "#ff0000"\n'
assert.deepEqual(Array.from(Model.lanesFrom(toml, "#ffffff")),
  ["#ff8800", "#00ff00", "#ff00ff", "#00ffff", "#ff0000", "#ffffff"])
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
assert.equal(Model.findCommit(log, "a1").id, "a1")

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

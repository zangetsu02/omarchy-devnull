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

console.log("Model.js: all checks passed")

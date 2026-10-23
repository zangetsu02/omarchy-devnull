// Run with: node tests/tui-test.mjs
// The character grid of the log: what the rail draws, line by line. Keeping it
// here rather than in QML is what makes the TUI testable at all.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import vm from "node:vm"

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "..", "qml", "data", "Model.js"), "utf8")
  .replace(".pragma library", "")
const Model = {}
vm.createContext(Model)
vm.runInContext(source, Model)

const G = Model.GLYPHS

// The node: one marker, the way LazyVim keeps one. Filled is the cursor.
assert.equal(Model.nodeGlyph({}, true), G.nodeHere)
assert.equal(Model.nodeGlyph({}, false), G.node)
// A deleted commit keeps its place, as the drawn rail already did.
assert.equal(Model.nodeGlyph({ deleted_at: "2026-10-21T00:00:00Z" }, false), G.nodeGone)
assert.equal(Model.nodeGlyph({ deleted_at: "2026-10-21T00:00:00Z" }, true), G.nodeGone)

// The rail under a commit, per kind of line.
assert.equal(Model.rail("body", {}), G.bar)
assert.equal(Model.rail("reply", { last: false }), G.branch + G.dash + G.arm)
assert.equal(Model.rail("reply", { last: true }), G.lastBranch + G.dash + G.arm)
// An unknown kind draws nothing rather than breaking the grid.
assert.equal(Model.rail("whatever", {}), " ")

// Every glyph is declared in one place and is a single code point. Whether the
// FONT actually serves it at one cell is a question fontconfig answers, not
// node: tests/glyph-test asks it. Counting code points here proved nothing —
// `⤷` is one code point and one and a half cells, and shipped broken because
// this assertion passed.
for (const [name, glyph] of Object.entries(G))
  assert.equal([...glyph].length, 1, `GLYPHS.${name} is not a single code point`)

// The header of a row, in two pieces. It used to be one string padded to a
// column count; the padding was a lie, because glyph positions round to whole
// pixels, so the line painted wider than its column and Qt elided the counts
// away. The right piece is anchored by QML instead, and nothing is computed.
const commit = { short_hash: "d453634", author: { username: "zangetsu02" },
                 stars_count: 4, starred: true, replies_count: 1,
                 created_at: new Date(Date.now() - 120000).toISOString() }

assert.equal(Model.headerLeft(commit), "d453634  @zangetsu02")
assert.equal(Model.headerRight(commit), "2m   " + G.star + " 4   " + G.replies + " 1")

// No stars, no star count: an empty slot reads quieter than a zero.
const bare = { short_hash: "36795c7", author: { username: "ndk98z" },
               stars_count: 0, starred: false, replies_count: 0,
               created_at: new Date(Date.now() - 180000).toISOString() }
assert.equal(Model.headerLeft(bare), "36795c7  @ndk98z")
assert.equal(Model.headerRight(bare), "3m")

// A commit still in moderation says so, next to its age.
assert.ok(Model.headerRight({ ...commit, status: "pending" }).includes("held"))

// An author the server did not send does not crash the line.
assert.equal(Model.headerLeft({ short_hash: "0000000" }), "0000000  @?")
assert.equal(Model.headerLeft(null), "")
assert.equal(Model.headerRight(null), "")

// --- Frames -----------------------------------------------------------------

// A titled top border fills its width exactly, whatever the title.
const top = Model.frameLine("top", 40, "commit d453634")
assert.equal([...top].length, 40)
assert.ok(top.startsWith("┌─ commit d453634 ─"))
assert.ok(top.endsWith("┐"))

// Untitled, and the bottom.
assert.equal(Model.frameLine("top", 10, ""), "┌────────┐")
assert.equal(Model.frameLine("bottom", 10, ""), "└────────┘")
assert.equal([...Model.frameLine("bottom", 37, "")].length, 37)

// A title longer than the frame is cut, never wrapped: the border is one line.
const squeezed = Model.frameLine("top", 16, "a".repeat(40))
assert.equal([...squeezed].length, 16)
assert.ok(squeezed.endsWith("┐"))
assert.ok(squeezed.includes(G.ellipsis))

// Too narrow to hold a title at all still gives a valid border.
assert.equal([...Model.frameLine("top", 4, "wide title")].length, 4)
assert.equal([...Model.frameLine("top", 2, "x")].length, 2)
// A width below two cannot be drawn; it gives nothing rather than a stray corner.
assert.equal(Model.frameLine("top", 1, ""), "")
assert.equal(Model.frameLine("top", 0, ""), "")

// --- Signed out -------------------------------------------------------------

// The public page's shape is normalised in the bridge, where the fetch is, and
// tests/read-test is the test of record for it: a second copy of that rule here
// would be a second thing to keep in step.

// Never paired is NOT an error: it has its own kind, it says nothing, and it
// must never count toward the three strikes that mean "re-pair me".
assert.equal(Model.errorLine({ kind: "unpaired", error: "No key" }), "")
assert.equal(Model.nextFailureCount(2, { kind: "unpaired" }), 2)
assert.equal(Model.isBroken(Model.nextFailureCount(0, { kind: "unpaired" })), false)
// Revoked still is an error, and still counts.
assert.match(Model.errorLine({ kind: "auth", error: "x" }), /setup-devnull/)
assert.equal(Model.nextFailureCount(2, { kind: "auth" }), 3)

// Signed out, the panel reads the public feed instead of the API.
assert.deepEqual(Array.from(Model.tickCalls({ signedOut: true })), ["publicFeed"])
assert.deepEqual(Array.from(Model.tickCalls({ panelOpen: true, signedOut: true })), ["publicFeed"])
assert.deepEqual(Array.from(Model.openCalls({ signedOut: true })), ["publicFeed"])
// Signed in, nothing changes.
assert.deepEqual(Array.from(Model.tickCalls({})), ["me"])
assert.deepEqual(Array.from(Model.openCalls({})), ["notifications", "feed"])

console.log("Model.js: tui checks passed")

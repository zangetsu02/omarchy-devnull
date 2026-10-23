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
// The gap between commits keeps the lane alive only while something follows.
assert.equal(Model.rail("gap", { below: true }), G.bar)
assert.equal(Model.rail("gap", { below: false }), " ")
// An unknown kind draws nothing rather than breaking the grid.
assert.equal(Model.rail("whatever", {}), " ")

// Every glyph is declared in one place and is a single code point. Whether the
// FONT actually serves it at one cell is a question fontconfig answers, not
// node: tests/glyph-test asks it. Counting code points here proved nothing —
// `⤷` is one code point and one and a half cells, and shipped broken because
// this assertion passed.
for (const [name, glyph] of Object.entries(G))
  assert.equal([...glyph].length, 1, `GLYPHS.${name} is not a single code point`)

// The header of a row: hash, handle, age, then the counts pushed right.
const row = Model.headerFor(
  { short_hash: "d453634", author: { username: "zangetsu02" },
    stars_count: 4, starred: true, replies_count: 1,
    created_at: new Date(Date.now() - 120000).toISOString() },
  58)
assert.ok(row.startsWith("d453634  @zangetsu02"))
assert.ok(row.includes(G.star + " 4"))
assert.ok(row.includes(G.replies + " 1"))
assert.equal([...row].length, 58, "the header must fill its column exactly")

// No stars, no star count: an empty slot reads quieter than "☆ 0".
const bare = Model.headerFor(
  { short_hash: "36795c7", author: { username: "ndk98z" },
    stars_count: 0, starred: false, replies_count: 0,
    created_at: new Date(Date.now() - 180000).toISOString() },
  58)
assert.ok(!bare.includes(G.star) && !bare.includes(G.unstarred))
assert.ok(!bare.includes(G.replies))
assert.equal([...bare].length, 58)

// A commit still in moderation says so INSIDE the padded line: appending it
// afterwards pushed exactly those rows a word wider than every other.
const held = Model.headerFor(
  { short_hash: "bbbbbbb", author: { username: "zangetsu02" }, status: "pending",
    stars_count: 0, replies_count: 0, created_at: new Date().toISOString() },
  58)
assert.ok(held.includes("held"))
assert.equal([...held].length, 58)

// A width that is not a number must not throw: QML asks before it has measured.
assert.equal(Model.headerFor({}, NaN), "")
assert.equal(Model.headerFor({}, Infinity), "")
assert.equal(Model.frameLine("top", NaN, "x"), "")
assert.equal(Model.frameLine("top", Infinity, "x"), "")

// A handle long enough to crowd the counts is cut, never wrapped: the grid
// has one line here and the counts matter more than the last letters.
const long = Model.headerFor(
  { short_hash: "aaaaaaa", author: { username: "a".repeat(60) },
    stars_count: 12, starred: true, replies_count: 3,
    created_at: new Date(Date.now() - 60000).toISOString() },
  58)
assert.equal([...long].length, 58)
assert.ok(long.includes(G.star + " 12"))
assert.ok(long.includes(G.ellipsis))

// --- The command line -------------------------------------------------------

// What is typed, split into a verb and the rest. The leading colon is the
// prompt, not part of the command.
assert.deepEqual({ ...Model.parseCommand(":log latest") }, { name: "log", arg: "latest" })
assert.deepEqual({ ...Model.parseCommand("log latest") }, { name: "log", arg: "latest" })
assert.deepEqual({ ...Model.parseCommand(":refresh") }, { name: "refresh", arg: "" })
assert.deepEqual({ ...Model.parseCommand(":") }, { name: "", arg: "" })
assert.deepEqual({ ...Model.parseCommand("   ") }, { name: "", arg: "" })
// An argument keeps its inner spaces; only the edges go.
assert.equal(Model.parseCommand(":profile  @zangetsu02  ").arg, "@zangetsu02")

// Completion: everything on an empty prompt, narrowed as you type.
assert.ok(Model.commandsFor("").length >= 8)
assert.deepEqual(Array.from(Model.commandsFor(":sta").map(c => c.name)), ["star", "starred"])
assert.deepEqual(Array.from(Model.commandsFor(":starr").map(c => c.name)), ["starred"])
assert.deepEqual(Array.from(Model.commandsFor(":nope").map(c => c.name)), [])
// Each one carries the line the prompt shows beside it.
for (const command of Model.commandsFor(""))
  assert.ok(command.help && command.help.length > 0, `${command.name} has no help`)
// Once a command is complete and an argument is being typed, stop suggesting.
assert.deepEqual(Array.from(Model.commandsFor(":log latest").map(c => c.name)), [])

// Every command maps to something the panel can actually do.
const known = new Set(["log", "notifications", "starred", "profile", "refresh",
                       "star", "open", "copy", "reply", "connect", "quit"])
for (const command of Model.commandsFor(""))
  assert.ok(known.has(command.name), `${command.name} is not wired to anything`)

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

// The public feed comes from the home page's embedded props, which name things
// differently from the API. One shape reaches the views, whichever door it came
// through.
const pub = Model.normalizePublic({
  id: "01a15d37-0511-7071-a1ae-d28a502b4a24",
  body: "hello", user: { username: "zangetsu02", name: "christian" },
  stars_count: 4, starred: false, replies_count: 1, status: "approved",
  created_at: "2026-10-21T07:12:00.000000Z",
})
// short_hash is the last seven of the id without its dashes (CommitResource:57).
assert.equal(pub.short_hash, "02b4a24")
assert.equal(pub.author.username, "zangetsu02")
assert.equal(pub.html_url, "https://dev-null.sh/@zangetsu02/commits/02b4a24")
assert.equal(pub.stars_count, 4)
// A row built from it draws exactly like one from the API.
assert.equal(Model.rowFor(pub).handle, "@zangetsu02")
assert.equal([...Model.headerFor(pub, 58, Date.parse(pub.created_at))].length, 58)
// Nothing to normalise, nothing thrown.
assert.equal(Model.normalizePublic(null), null)
assert.equal(Model.normalizePublic({}).short_hash, "")

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

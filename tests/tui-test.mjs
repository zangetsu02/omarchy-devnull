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

// The node: one marker, the way LazyVim keeps one. Filled is the cursor.
assert.equal(Model.nodeGlyph({}, true), "●")
assert.equal(Model.nodeGlyph({}, false), "○")
// A deleted commit keeps its place, as the drawn rail already did.
assert.equal(Model.nodeGlyph({ deleted_at: "2026-10-21T00:00:00Z" }, false), "◌")
assert.equal(Model.nodeGlyph({ deleted_at: "2026-10-21T00:00:00Z" }, true), "◌")

// The rail under a commit, per kind of line.
assert.equal(Model.rail("body", {}), "│")
assert.equal(Model.rail("reply", { last: false }), "├─⤷")
assert.equal(Model.rail("reply", { last: true }), "╰─⤷")
// The gap between commits keeps the lane alive only while something follows.
assert.equal(Model.rail("gap", { below: true }), "│")
assert.equal(Model.rail("gap", { below: false }), " ")
// An unknown kind draws nothing rather than breaking the grid.
assert.equal(Model.rail("whatever", {}), " ")

// Every glyph the rail can draw is one column wide: a two-cell glyph would
// shear every line under it.
for (const glyph of ["●", "○", "◌", "│", "├", "╰", "─", "⤷"])
  assert.equal([...glyph].length, 1, `${glyph} is not a single code point`)

// The header of a row: hash, handle, age, then the counts pushed right.
const row = Model.headerFor(
  { short_hash: "d453634", author: { username: "zangetsu02" },
    stars_count: 4, starred: true, replies_count: 1,
    created_at: new Date(Date.now() - 120000).toISOString() },
  58)
assert.ok(row.startsWith("d453634  @zangetsu02"))
assert.ok(row.includes("★ 4"))
assert.ok(row.includes("⤷ 1"))
assert.equal([...row].length, 58, "the header must fill its column exactly")

// No stars, no star count: an empty slot reads quieter than "☆ 0".
const bare = Model.headerFor(
  { short_hash: "36795c7", author: { username: "ndk98z" },
    stars_count: 0, starred: false, replies_count: 0,
    created_at: new Date(Date.now() - 180000).toISOString() },
  58)
assert.ok(!bare.includes("★"))
assert.ok(!bare.includes("⤷"))
assert.equal([...bare].length, 58)

// A handle long enough to crowd the counts is cut, never wrapped: the grid
// has one line here and the counts matter more than the last letters.
const long = Model.headerFor(
  { short_hash: "aaaaaaa", author: { username: "a".repeat(60) },
    stars_count: 12, starred: true, replies_count: 3,
    created_at: new Date(Date.now() - 60000).toISOString() },
  58)
assert.equal([...long].length, 58)
assert.ok(long.includes("★ 12"))
assert.ok(long.includes("…"))

console.log("Model.js: tui checks passed")

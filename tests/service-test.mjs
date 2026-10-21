// Run with: node tests/service-test.mjs
// The sequencing the panel must obey, checked against the real functions rather
// than a copy of them: Service.qml does nothing these do not tell it to do.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import vm from "node:vm"
// Model.js runs in its own vm context, so its arrays are copied into this realm
// before comparison: deepEqual otherwise trips on the prototype, not the values.

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "..", "Model.js"), "utf8").replace(".pragma library", "")
const Model = {}
vm.createContext(Model)
vm.runInContext(source, Model)

// Closed, a tick asks /me and nothing else — listing notifications would mark
// them read on the website and in the official app.
assert.deepEqual(Array.from(Model.tickCalls(false, false)), ["me"])

// Opening asks for the notifications once, and the feed.
assert.deepEqual(Array.from(Model.openCalls()), ["notifications", "feed"])

// Ticking while open refreshes the feed only: the notifications are read already.
assert.deepEqual(Array.from(Model.tickCalls(true, false)), ["feed"])

// Three auth failures in a row, and it goes broken and stops calling.
let failures = 0
for (let i = 0; i < 3; i++) failures = Model.nextFailureCount(failures, { kind: "auth" })
assert.equal(Model.isBroken(failures), true)
assert.deepEqual(Array.from(Model.tickCalls(false, true)), [])
assert.deepEqual(Array.from(Model.tickCalls(true, true)), [])

// Two is not three: the plugin does not give up on the first hiccup.
assert.equal(Model.isBroken(Model.nextFailureCount(1, { kind: "auth" })), false)

// Review Focus: a network failure is not a 401 — it must never trip the re-pair
// state, however long the wifi stays down.
let offline = 0
for (let i = 0; i < 5; i++) offline = Model.nextFailureCount(offline, { kind: "network" })
assert.equal(offline, 0)
assert.equal(Model.isBroken(offline), false)

// Nor does a wrong clock, which shares its 401 with a revoked device upstream.
let skewed = 0
for (let i = 0; i < 5; i++) skewed = Model.nextFailureCount(skewed, { kind: "expired" })
assert.equal(Model.isBroken(skewed), false)

// Recovering clears the count without a restart.
assert.equal(Model.nextFailureCount(2, null), 0)

// What the panel shows for each kind, so a failure is never a silent one.
assert.match(Model.errorLine({ kind: "expired", error: "Signature expired." }), /clock/i)
assert.match(Model.errorLine({ kind: "auth", error: "Not approved." }), /setup-devnull/)
assert.match(Model.errorLine({ kind: "rules", error: "" }), /rules/i)
assert.equal(Model.errorLine({ kind: "http", error: "Boom." }), "Boom.")
assert.equal(Model.errorLine(null), "")

// A star is applied before the server answers, and put back if it refuses.
const before = { id: "a", starred: false, stars_count: 4 }
const after = Model.withStar(before, true)
assert.equal(after.starred, true)
assert.equal(after.stars_count, 5)
assert.equal(Model.withStar(after, false).stars_count, 4)
// The optimistic count never goes below zero, whatever the server said before.
assert.equal(Model.withStar({ id: "a", starred: true, stars_count: 0 }, false).stars_count, 0)

// A refused reply keeps what was typed; an accepted one clears it.
assert.equal(Model.keepsDraft({ error: "The body field is required.", kind: "http" }), true)
assert.equal(Model.keepsDraft({ id: "new", status: "pending" }), false)
assert.equal(Model.keepsDraft(null), false)

// Drafts are held per commit id, because the feed is replaced wholesale on
// every refresh and an index would point at whatever slid into that slot.
let drafts = Model.withDraft({}, "a", "half a thou")
drafts = Model.withDraft(drafts, "b", "another")
assert.equal(Model.draftFor(drafts, "a"), "half a thou")
assert.equal(Model.draftFor(drafts, "b"), "another")
assert.equal(Model.draftFor(drafts, "missing"), "")
assert.equal(Model.draftFor(null, "a"), "")
drafts = Model.clearDraft(drafts, "a")
assert.equal(Model.draftFor(drafts, "a"), "")
assert.equal(Model.draftFor(drafts, "b"), "another")

// Once older pages are loaded, the timer must stop replacing the feed with
// page one — it would throw away everything the user scrolled to.
assert.deepEqual(Array.from(Model.tickCalls(true, false, false)), ["feed"])
assert.deepEqual(Array.from(Model.tickCalls(true, false, true)), [])
assert.deepEqual(Array.from(Model.tickCalls(false, false, true)), ["me"])

// Opening the panel while broken probes once, so re-pairing is noticed without
// restarting the shell.
assert.deepEqual(Array.from(Model.openCalls(false)), ["notifications", "feed"])
assert.deepEqual(Array.from(Model.openCalls(true)), ["me"])

console.log("service: all checks passed")

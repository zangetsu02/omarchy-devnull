# dev-null in the Omarchy bar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A QuickShell bar widget that shows the dev-null.sh feed, lights up when something is unread, and can star and reply — everything else opens the website.

**Architecture:** A python3 CLI, `scripts/devnull`, owns the signing key and every HTTP call, and prints one JSON object per invocation. `Service.qml` runs it and holds the state; `Model.js` holds the pure formatting and the polling arithmetic so both can be tested without a desktop. This is the same QML-over-a-bridge-script shape as `zangetsu.electroline` next door.

**Tech Stack:** QuickShell/QML (Omarchy 4.0.4 bar widget), python3 standard library only, `ssh-keygen -Y sign` for signatures, node for the `Model.js` checks.

**Spec:** `docs/superpowers/specs/2026-10-21-omarchy-devnull-design.md`

## Global Constraints

- **Signed message:** `<unix timestamp>\n<nonce>\n<METHOD>\n<path and query>\n<body>`, joined with `\n`, no trailing newline.
- **Headers:** `X-Devnull-Timestamp`, `X-Devnull-Nonce`, `X-SSH-Signature`.
- **SSH signature namespace:** `devnull-api` for the API. (`devnull-commit` is the other, unused, door.)
- **Nonce:** must match `^[0-9a-f]{32}$` — 16 random bytes, hex.
- **Clock skew:** the server allows 300 seconds either way.
- **Body of a signed request:** JSON, and the raw bytes sent are the bytes signed.
- **Commit body:** 1 to 4000 characters counted the site's way, 40000 raw maximum.
- **Feed log key:** `latest`. (`following` and `trending` also exist; unused.)
- **Pairing:** `redirect_uri` must start with `devnull://`; an authorization code expires after 5 minutes and is single-use.
- **Rate limits:** 120 signed requests a minute, 60 stars a minute.
- **Base URL:** `https://dev-null.sh`, overridable with `DEVNULL_URL` so the tests can point at the mock.
- **State directory:** `~/.local/share/omarchy-devnull/`, key file mode 0600.
- **No dependencies.** Python standard library and `ssh-keygen`, nothing installed, no virtualenv.
- **Manifest:** `schemaVersion: 1`, `kinds: ["bar-widget"]`, `id: zangetsu.devnull`.

## Review Focus

- **The clock is off by more than 300 seconds.** Every call fails with "Signature expired". The panel must say that once, in those words, and not retry in a loop. *(Task 1)*
- **The network is down.** A DNS or connection failure must never count toward the three 401s that trigger the re-pair state. *(Task 6)*
- **A reply is empty, whitespace only, or over 4000 characters.** The server answers 422; the panel shows the server's message and keeps the draft. *(Task 4)*
- **`x-scheme-handler/devnull` is already claimed.** Setup must say so and stop, rather than register itself silently or block forever waiting for a code that another program received. *(Task 2)*
- **A commit with an empty body** (an image or a poll carries it). The row must still render, with its hash and author, and still open. *(Task 5)*

---

### Task 1: Signing, and `devnull me`

**Files:**
- Create: `scripts/devnull`
- Test: `tests/signing-test`

**Interfaces:**
- Produces: `scripts/devnull me` → `{"user": {...}, "unread_notifications_count": N}` on stdout, exit 0. Every failure prints `{"error": "<line>", "kind": "<auth|expired|network|http>"}` and exits 1.
- Produces, for later tasks: `signed_message(timestamp, nonce, method, uri, body) -> str`, `sign(message) -> str`, `call(method, path, body=None) -> dict`.

- [ ] **Step 1: Write the failing test**

`tests/signing-test` is a python3 script, run directly. It imports `scripts/devnull` as a module and checks:

```python
# The message is the five fields joined by newlines, in order, nothing else.
assert signed_message("1771600000", "a" * 32, "GET", "/api/v1/me", "") == (
    "1771600000\n" + "a" * 32 + "\nGET\n/api/v1/me\n")
# A body is the fifth field, signed as the exact bytes that get sent.
assert signed_message("1771600000", "b" * 32, "POST", "/api/v1/commits",
                      '{"body":"hi"}').endswith('\n{"body":"hi"}')
# A nonce is 32 hex characters, and two in a row differ.
assert re.fullmatch(r"[0-9a-f]{32}", new_nonce())
assert new_nonce() != new_nonce()
# A signature over the message verifies against the key that made it.
# (generate a throwaway ed25519 key in a temp dir, sign, then verify with
#  `ssh-keygen -Y verify -n devnull-api` and an allowed_signers file)
assert verify_ok is True
# The namespace is not interchangeable: verifying under devnull-commit fails.
assert verify_under_other_namespace is False
# A clock-skew rejection is reported as its own kind, not as a generic error.
assert classify(400, "Signature expired. Check that your clock is right.") == "expired"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/signing-test`
Expected: FAIL — `scripts/devnull` does not exist.

- [ ] **Step 3: Write `scripts/devnull`**

A python3 script, no third-party imports, with a module docstring listing the
subcommands (electroline's bridge prints its docstring on a bare invocation;
do the same). This task implements:

- `signed_message(timestamp, nonce, method, uri, body)` — joins with `\n`.
- `new_nonce()` — `secrets.token_hex(16)`.
- `sign(message)` — writes the message to a temp file under `umask 077`, runs
  `ssh-keygen -Y sign -n devnull-api -f <key>`, returns the armored signature,
  deletes the temp files by name.
- `call(method, path, body=None)` — `urllib.request`, the three headers, JSON
  body encoded once and both signed and sent as those exact bytes.
- `classify(status, message)` — `auth` for 401, `expired` when the message
  says the signature expired, `network` for a `URLError`, `http` otherwise.
- `main()` — dispatches `me`, prints JSON, and turns any failure into the
  error envelope above. Never a traceback.

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/signing-test`
Expected: `signing: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add scripts/devnull tests/signing-test
git commit -m "Sign API requests with an SSH key"
```

---

### Task 2: Pairing

**Files:**
- Create: `scripts/setup-devnull`, `scripts/devnull-callback`
- Modify: `scripts/devnull` — add `pair <code> <verifier>`
- Test: `tests/pairing-test`

**Interfaces:**
- Consumes: `call()` and the error envelope from Task 1.
- Produces: a key at `~/.local/share/omarchy-devnull/id_ed25519` (0600) and a `device.json` beside it holding the username and the fingerprint. Everything after this task assumes both exist.

- [ ] **Step 1: Write the failing test**

`tests/pairing-test`, python3, offline:

```python
# PKCE: the challenge is the url-safe base64 of the SHA-256 of the verifier,
# unpadded, and matches the server's ^[A-Za-z0-9_-]{43}$.
assert challenge_for("x" * 64) == base64.urlsafe_b64encode(
    hashlib.sha256(b"x" * 64).digest()).decode().rstrip("=")
assert re.fullmatch(r"[A-Za-z0-9_-]{43}", challenge_for(new_verifier()))
# The fingerprint sent is the server's shape.
assert re.fullmatch(r"SHA256:[A-Za-z0-9+/]{43}", fingerprint_of(tmp_key))
# The authorize URL carries all six parameters and a devnull:// redirect.
params = parse_qs(urlparse(authorize_url(...)).query)
assert set(params) == {"fingerprint", "device_name", "code_challenge",
                       "code_challenge_method", "state", "redirect_uri"}
assert params["code_challenge_method"] == ["S256"]
assert params["redirect_uri"][0].startswith("devnull://")
# A code coming back under a different state is refused.
assert accepts_callback(state="abc", url="devnull://cb?code=1&state=zzz") is False
# Review Focus: a scheme handler owned by something else stops the setup.
assert handler_conflict("firefox.desktop") is True
assert handler_conflict("omarchy-devnull-callback.desktop") is False
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/pairing-test`
Expected: FAIL — `scripts/setup-devnull` does not exist.

- [ ] **Step 3: Write the two scripts and the `pair` subcommand**

`scripts/devnull-callback` is three lines: it takes the `devnull://…` URL it was
opened with and writes it to the FIFO at
`$XDG_RUNTIME_DIR/omarchy-devnull/callback`.

`scripts/setup-devnull`, in order:

1. Generate the ed25519 key if absent, mode 0600, no passphrase, never added
   to the agent.
2. Check `xdg-mime query default x-scheme-handler/devnull`. If something other
   than ours owns it, print what owns it and stop.
3. Write `~/.local/share/applications/omarchy-devnull-callback.desktop` with
   `MimeType=x-scheme-handler/devnull`, register it, `update-desktop-database`.
4. Make the FIFO, generate verifier, challenge and state, `xdg-open` the
   authorize URL.
5. Read the FIFO with a 5 minute timeout — the life of a code — checking
   `state` and surfacing an `error=access_denied` as "you cancelled it".
6. `scripts/devnull pair <code> <verifier>`, which POSTs to `/api/v1/devices`
   signed by the new key, and writes `device.json` from the answer.
7. Print the username it paired as, and remind him to accept the commit rules
   on the site once, or `RequireCommitRules` will refuse his replies.

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/pairing-test`
Expected: `pairing: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-devnull scripts/devnull-callback scripts/devnull tests/pairing-test
git commit -m "Pair a key as a device"
```

---

### Task 3: The mock, and reading

**Files:**
- Create: `tests/mock-devnull`
- Modify: `scripts/devnull` — add `feed [--cursor C]`, `notifications`
- Test: `tests/read-test`

**Interfaces:**
- Consumes: `call()` from Task 1.
- Produces: `devnull feed` → `{"commits": [...], "next_cursor": "..."}`, `devnull notifications` → `{"notifications": [...], "read_at": "..."}`. Each commit keeps the server's own fields: `id`, `short_hash`, `body`, `user`, `stars_count`, `starred`, `status`, `html_url`, `created_at`, `replies_count`.

- [ ] **Step 1: Write the failing test**

`tests/mock-devnull` is a `http.server` stand-in, as electroline's `tests/mock-cloud` is, serving `/api/v1/me`, `/api/v1/log/latest`, `/api/v1/notifications`, the two star routes and `POST /api/v1/commits`. It verifies the three signature headers are present and well-formed, refuses a reused nonce with 400, and records whether `/notifications` was called.

`tests/read-test` starts it on a free port, points `DEVNULL_URL` at it, and checks:

```python
# The feed comes back as a list, newest first, with the fields the panel needs.
assert [c["short_hash"] for c in feed()["commits"]] == ["d453634", "36795c7"]
assert feed()["next_cursor"] == "eyJpZCI6..."
# A second page is asked for with the cursor, on the query string that got signed.
assert mock.last_uri == "/api/v1/log/latest?cursor=eyJpZCI6..."
# `me` does not touch notifications — the whole point of the design.
me(); assert mock.notifications_calls == 0
# `notifications` does, once, and hands back the boundary.
notifications(); assert mock.notifications_calls == 1
assert notifications()["read_at"].endswith("Z")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/read-test`
Expected: FAIL — unknown subcommand `feed`.

- [ ] **Step 3: Add the two read subcommands**

`feed` calls `GET /api/v1/log/latest`, passing `?cursor=` when given one.
`notifications` calls `GET /api/v1/notifications` with no filter. Both return
the server's JSON with nothing dropped.

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/read-test`
Expected: `read: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add tests/mock-devnull tests/read-test scripts/devnull
git commit -m "Read the feed and the notifications"
```

---

### Task 4: Starring and replying

**Files:**
- Modify: `scripts/devnull` — add `star <id>`, `unstar <id>`, `reply <id> <body>`
- Test: `tests/write-test`

**Interfaces:**
- Consumes: the mock from Task 3.
- Produces: `devnull star <id>` → `{"starred": true, "stars_count": N}`; `devnull reply <id> <body>` → `{"id": "...", "status": "pending"|"approved", "short_hash": "..."}`.

- [ ] **Step 1: Write the failing test**

```python
# A star is a POST with no body, and the signed URI is the star route.
assert star(ID)["starred"] is True
assert mock.last_method == "POST" and mock.last_uri == f"/api/v1/commits/{ID}/star"
# Un-starring is the same route, deleted.
assert unstar(ID)["starred"] is False and mock.last_method == "DELETE"
# A reply sends body and parent_id as JSON, and the bytes signed are the bytes sent.
reply(ID, "Agreed")
assert json.loads(mock.last_body) == {"body": "Agreed", "parent_id": ID}
assert mock.signature_covered_body is True
# A moderated reply reports what came back, not an assumption.
assert reply(ID, "Agreed")["status"] == "pending"
# Review Focus: the server's 422 reaches the caller as its own text.
mock.next_response = (422, {"message": "The body field is required."})
assert reply(ID, "  ")["error"] == "The body field is required."
assert reply(ID, "x" * 4001)["kind"] == "http"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/write-test`
Expected: FAIL — unknown subcommand `star`.

- [ ] **Step 3: Add the three write subcommands**

`star`/`unstar` are `POST`/`DELETE` on `/api/v1/commits/{id}/star` with an empty
body. `reply` is `POST /api/v1/commits` with `{"body": ..., "parent_id": ...}`.
A 422 is surfaced with the server's `message` as the error line; the body is
sent as typed, with no client-side trimming or truncation — the server owns
those rules.

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/write-test`
Expected: `write: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add scripts/devnull tests/write-test
git commit -m "Star and reply"
```

---

### Task 5: Model.js

**Files:**
- Create: `Model.js`
- Test: `tests/model-test.mjs`

**Interfaces:**
- Produces: `clampBody(text, lines, width) -> string`, `rowFor(commit) -> {hash, handle, body, stars, starred, url}`, `summaryFor(notificationGroup) -> string`, `badgeFor(count, broken) -> {text, state}`, `pollDelay(panelOpen, settings) -> ms`.

- [ ] **Step 1: Write the failing test**

`tests/model-test.mjs`, loaded the way electroline loads its own — read the
source, strip `.pragma library`, run it in a `node:vm` context.

```js
// Two lines and an ellipsis, never a broken word in the middle.
assert.equal(Model.clampBody("alpha beta gamma delta", 2, 11), "alpha beta\ngamma delta")
assert.equal(Model.clampBody("a".repeat(400), 2, 20).split("\n").length, 2)
assert.ok(Model.clampBody("x ".repeat(300), 2, 20).endsWith("…"))
// Review Focus: an empty body still gives a row worth drawing.
const bare = Model.rowFor({ id: "u", short_hash: "d453634", body: "",
  user: { username: "zangetsu02" }, stars_count: 0, html_url: "https://dev-null.sh/x" })
assert.equal(bare.hash, "d453634")
assert.equal(bare.handle, "@zangetsu02")
assert.equal(bare.body, "")
assert.ok(bare.url.length > 0)
// The badge: dark at zero, a count up to 99, then 99+, and broken wins.
assert.deepEqual(Model.badgeFor(0, false), { text: "", state: "quiet" })
assert.deepEqual(Model.badgeFor(7, false), { text: "7", state: "unread" })
assert.equal(Model.badgeFor(250, false).text, "99+")
assert.equal(Model.badgeFor(3, true).state, "broken")
// Closed polls slowly, open polls fast, and the settings are honoured.
assert.equal(Model.pollDelay(false, { refreshIntervalSec: 60 }), 60000)
assert.equal(Model.pollDelay(true, { openRefreshIntervalSec: 20 }), 20000)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `node tests/model-test.mjs`
Expected: FAIL — cannot find `Model.js`.

- [ ] **Step 3: Write `Model.js`**

A `.pragma library` of pure functions, no QML imports, nothing that reaches the
network or the filesystem.

- [ ] **Step 4: Run it to verify it passes**

Run: `node tests/model-test.mjs`
Expected: `Model.js: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Model.js tests/model-test.mjs
git commit -m "Format rows, badges and poll delays"
```

---

### Task 6: Service.qml

**Files:**
- Create: `Service.qml`
- Test: `tests/service-test` (drives `scripts/devnull` against the mock the way `Service.qml` does, since QML cannot be unit tested here)

**Interfaces:**
- Consumes: every `scripts/devnull` subcommand, and all of `Model.js`.
- Produces, as QML properties read by Task 7: `unreadCount:int`, `commits:var`, `notifications:var`, `loading:bool`, `broken:bool`, `lastError:string`, `panelOpen:bool`; and the methods `refresh()`, `openPanel()`, `closePanel()`, `toggleStar(id)`, `sendReply(id, body)`, `loadMore()`.

- [ ] **Step 1: Write the failing test**

`tests/service-test` reproduces the call *sequence* the service must make:

```python
# Closed, a tick asks /me and nothing else.
tick(panel_open=False); assert mock.calls == ["/api/v1/me"]
# Opening asks for notifications once and the feed once.
open_panel(); assert mock.calls == ["/api/v1/notifications", "/api/v1/log/latest"]
# Ticking while open refreshes the feed only — the notifications are read already.
tick(panel_open=True); assert mock.calls == ["/api/v1/log/latest"]
# Three 401s in a row, and it goes broken and stops calling.
for _ in range(3): mock.next_status = 401; tick()
assert service.broken is True and mock.calls == []
# Review Focus: a network failure is not a 401 — it must never trip the re-pair state.
for _ in range(5): mock.offline = True; tick()
assert service.broken is False and service.lastError != ""
# Recovering clears the error without a restart.
mock.offline = False; tick(); assert service.lastError == ""
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/service-test`
Expected: FAIL — the call sequence is empty.

- [ ] **Step 3: Write `Service.qml`**

A `Process` from `Quickshell.Io` per call with a `StdioCollector`, as electroline
does. The two timers come from `Model.pollDelay`. A 401 increments a counter
that only a success resets; `kind: "network"` leaves it untouched. `toggleStar`
applies the change locally first and puts it back if the call fails.

- [ ] **Step 4: Run it to verify it passes**

Run: `tests/service-test`
Expected: `service: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Service.qml tests/service-test
git commit -m "Poll without eating the inbox"
```

---

### Task 7: The widget

**Files:**
- Create: `manifest.json`, `Panel.qml`, `DevNullIcon.qml`

**Interfaces:**
- Consumes: every property and method on `Service.qml`, and `Model.js` for formatting.
- Produces: the plugin the bar can finally load. `entryPoints.barWidget` is `Panel.qml`.

- [ ] **Step 1: Write `manifest.json`**

`schemaVersion: 1`, `id: zangetsu.devnull`, `kinds: ["bar-widget"]`,
`defaultSection: "right"`, `allowMultiple: false`, and a settings schema with
`refreshIntervalSec` (default 60, 30–3600), `openRefreshIntervalSec`
(default 20, 5–120) and `feedLength` (default 50). Each `description` says why
the value is what it is, as electroline's do.

- [ ] **Step 2: Write `DevNullIcon.qml` and `Panel.qml`**

The icon takes `Model.badgeFor` and draws three states: quiet, a count, and
broken. The panel is notifications above, feed below, each row a hash, a
handle, two clamped lines and a star; a reply field opens under a row and
reports what came back. Clicking a row opens its `html_url` with `xdg-open`.
Colours come from the Omarchy theme, body text is monospace.

- [ ] **Step 3: Run it in the bar**

Run: `omarchy-restart-shell` (or restart the shell the way Omarchy does), then
open the panel.
Expected: the icon appears, the panel lists real commits, a star sticks, a
reply reports its status.

- [ ] **Step 4: Run every test once more**

Run: `tests/signing-test && tests/pairing-test && tests/read-test && tests/write-test && tests/service-test && node tests/model-test.mjs`
Expected: all six print their pass line.

- [ ] **Step 5: Commit**

```bash
git add manifest.json Panel.qml DevNullIcon.qml
git commit -m "Put dev-null in the bar"
```

---

### Task 8: README, and one real reply

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the README**

Electroline's shape: what it does, **why it goes through the device-pairing
flow** (the API is the mobile app's, the key need not be on GitHub, the
namespace means it cannot sign anything else), the one setup command, the
settings, and the honest limits — moderation can hold a reply, the badge counts
every kind of notification, and `devnull://` belongs to the official app.

- [ ] **Step 2: Pair for real**

Run: `scripts/setup-devnull`
Expected: it prints the username it paired as.

- [ ] **Step 3: One real reply, by hand**

Reply from the panel to one of his own commits. This is the only write this
project sends to the live site.
Expected: it appears on dev-null.sh, or the panel says it is held for
moderation — whichever the server said.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Explain the thing"
```

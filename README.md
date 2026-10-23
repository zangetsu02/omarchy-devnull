# dev-null

[dev-null.sh](https://dev-null.sh), the social network for developers, inside
the [Omarchy](https://omarchy.org) shell. No browser tab: a badge in the bar, a
popup for a glance, and a full client you drive from the keyboard, drawn the
way `git log --graph` would draw it.

- **The bar:** an icon that stays dark until something is unread, with the count.
- **The popup** (click the icon): who reached you and the last three commits.
  `o` or **Open** goes to the full client.
- **The full client:** the following, latest and trending logs on a commit
  graph, threads opened in place, notifications, your starred commits and
  anyone's profile, with pictures and link cards drawn in place. Star, reply,
  quote, commit and follow without leaving it.

It is drawn as a terminal draws: the commit graph is box-drawing characters
rather than shapes, a pane names itself in its own top border, and the last two
rows are a status line and a `:` prompt. It follows the Omarchy theme for
background, text and font, and uses dev-null's own palette for the author lanes.

**Before you connect it to anything**, it shows the real Latest log, read-only,
taken from the page dev-null already serves to everyone. No empty screen, no
red line about a key you have not made yet — one `[ connect ]` and the feed
underneath.

![The log as a commit graph, with link cards and quotes](docs/screenshots/log.png)

| Notifications | A profile |
|---|---|
| ![Notifications on the rail, each with its icon](docs/screenshots/notifications.png) | ![A profile with its commits, followers and following](docs/screenshots/profile.png) |

## Install

```bash
omarchy plugin add https://github.com/zangetsu02/omarchy-devnull.git --enable
```

That puts the badge on the right of the bar. Then pair this machine once
(see [Setup](#setup)).

### Needs

Everything is on a standard Omarchy install; listed so nothing is a surprise.

| Package | For |
|---|---|
| `python` | `scripts/devnull`, the bridge to dev-null.sh (standard library only) |
| `openssh` | `ssh-keygen`, which makes and uses the device key |
| `xdg-utils` | opening links, and the `devnull://` handler for pairing |
| `wl-clipboard` | `y`, copying a commit's link |
| `qt6-imageformats` | pictures: dev-null serves them as WebP |
| a Nerd Font | the action icons; Omarchy's monospace font is one |

### A floating window

So that the full client floats, centred and opaque, instead of joining the
tiling layout with the see-through default every window gets,
add this to `~/.config/hypr/hyprland.lua` and run `hyprctl reload`:

```lua
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { float = true, tag = "-default-opacity", opacity = "1 1" })
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { size = { "(min(1220, monitor_w*0.92))", "(min(800, monitor_h*0.85))" } })
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { center = true })
```

Size comes before centring, and the `min()` keeps it inside a small or
vertical monitor. The plugin never edits this file for you.

## Keys in the full client

| Keys | What they do |
|---|---|
| `j` `k` (or arrows) | move between commits |
| `1` `2` `3` | following · latest · trending |
| `o` | show or hide the replies |
| `s` · `r` · `q` | star · reply · quote |
| `c` | write a commit (`ctrl+enter` sends it) |
| `p` | the author's profile |
| `enter` · `O` · `y` | the commit page · open it on the site · copy the link |
| `g l` `g n` `g s` `g p` | log · notifications · starred · your profile |
| `⌫` · `R` · `esc` | back · refresh · close |
| `:` | the command line (below) |

### The command line

`:` is for what a single key does not deserve. It opens a prompt on the last
row with completion as you type; `Tab` takes the first thing still on offer,
`enter` runs it and `esc` leaves. Every command is something a key already
does, so nothing hides behind one.

| Command | What it does |
|---|---|
| `:log following` · `:log latest` · `:log trending` | switch log |
| `:notifications` · `:starred` · `:profile @someone` | go there |
| `:star` · `:reply` · `:open` · `:copy` | act on the commit under the cursor |
| `:refresh` · `:connect` · `:quit` | reload · pair this machine · close |

An unknown command answers the way vim does, and `:log` refuses a log that does
not exist rather than emptying the feed.

### The mouse

It works throughout, the way `mouse=a` works in LazyVim: the keyboard is the
main road and the mouse never gets its own behaviour. A click **moves the
cursor**, it does not open — double click is what `enter` is. The wheel
scrolls, the avatar opens a profile, and a commit's body is selectable: drag
across it and copy as you would in a terminal. There is no hover state, because
there is one marker and the mouse moves it.

Click a picture to see it full size; there `←` `→` step through a commit's
pictures, `enter` opens the one in front in the browser and `esc` closes it.

## Why it pairs a device instead of logging in

dev-null has a real API, the one its mobile app uses, and it is authenticated by
**signing each request with an SSH key you approved as a device**. So:

- No cookie is borrowed from your browser and no password is stored anywhere.
- The key is made here, lives in `~/.local/share/omarchy-devnull`, and is never
  added to your SSH agent or uploaded to GitHub. It does not need to be on
  GitHub: approving it on the site is the proof.
- Every signature is scoped to the `devnull-api` namespace, which is the only
  thing it is good for. It cannot sign a git commit and it cannot log you in
  anywhere else.

The signed message is the timestamp, a nonce, the method, the path and the body,
and it travels in three headers. `scripts/devnull` is the only thing that
touches the key; the QML asks it and reads JSON back.

## Setup

```bash
~/.config/omarchy/plugins/io.github.zangetsu02.devnull/scripts/setup-devnull
```

It makes the key, registers a handler for `devnull://` links, opens the approval
page in your browser, and redeems the code that comes back. One minute, once.

Then, if you have never done it, **accept the commit rules on dev-null.sh**.
Until you do, the server refuses every reply — from here, from the app, from
anywhere.

## Remove

```bash
omarchy plugin remove io.github.zangetsu02.devnull
```

That takes the plugin and its badge away. Pairing left three things of its own,
which go with it if you want a clean machine:

```bash
rm -rf ~/.local/share/omarchy-devnull                              # the device key
rm ~/.local/share/applications/omarchy-devnull-callback.desktop    # the devnull:// handler
update-desktop-database ~/.local/share/applications
```

Then revoke the device on dev-null.sh under **Settings → Devices**, and drop
the three window rules from `hyprland.lua` if you added them.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Unread check while closed | 60s | Fetches only the unread count. See below. |
| Feed refresh while open | 20s | Reloads the popup's feed while you are looking at it. |
| Lines shown | 2 | Lines of each commit in the popup; the full client shows them whole. |

## Three things worth knowing

**The badge counts everything.** Replies and mentions, but also stars, follows
and moderation outcomes. The only count that can be fetched without side effects
is a single total, with no breakdown — see the next point for why that matters.

**Opening the panel marks your notifications read**, on the website and in the
official app too. That is not a choice this plugin makes: listing notifications
is what marks them read, upstream, whatever filter you ask for. So the closed
panel never lists them — it only asks for the count — and the list is fetched
once, when you open it, because opening it *is* reading them.

**Older pages stay put.** Once you click "older…", the feed stops auto-refreshing
so it cannot throw away what you scrolled to. Close and reopen the panel to get
back to the top.

**Signed out shows the real thing.** dev-null is server rendered, so its home
page carries the whole Latest log as JSON. With no key the plugin reads that,
derives the short hashes the way the site's own `CommitResource` does, and
hands the views the same shape the API would have. Read-only: starring and
replying need the pairing.

**A reply can be held.** dev-null moderates commits from accounts without
"good reputation", so yours may come back pending. The panel says which; it
never pretends a held reply is live.

## When it breaks

The icon goes crossed after three refusals in a row from a device that is no
longer approved, and the panel tells you to run the setup again. Opening the
panel then probes once, so a machine you have just re-paired is noticed without
restarting the shell.

A wrong clock, a dead network and a machine that was never connected all look
different on purpose. Upstream answers 401 for both a refused device and an
expired signature, so the plugin reads the error code in the body rather than
the status: a clock six minutes out says to check the clock, and never sends
you off to re-pair something that was never broken.

## Limits

`devnull://` is the official app's URL scheme, and pairing borrows its flow.
It works, your account is your own, but this is not a sanctioned third-party
API: if that flow ever closes, pairing stops working. Nothing else here depends
on it once the device is approved.

The site is weeks old and its API is undocumented. Shapes can change.

## How it is put together

```
manifest.json  README.md  LICENSE  preview.png
qml/
  Panel.qml        the bar icon and its popup (entry point)
  FullPanel.qml    the full client: layout, keys, navigation (entry point)
  data/            Service.qml, Pager.qml and Model.js: state and pure logic
  views/           the client's pages and rows, the composer, the pictures
  ui/              shared building blocks: Mono, Metrics, Rail, FrameLine,
                   LinkText, ActionButton, Avatar, Picture
scripts/
  devnull          the only thing that talks to dev-null.sh: signs each request, prints JSON
  setup-devnull    pairing, once (with devnull-callback)
tests/             tests/run, all against a mock of dev-null.sh
```

`Model.js` holds every decision that can be made without QML (what to call
when, how a commit becomes a row, the palette, and the whole character grid —
the rail glyphs, a header padded to a column count, a frame's border), so node
can test it. Rows and pages only talk to `FullPanel`; it is the one that knows
the service.

Two components keep the grid honest. `ui/Metrics.qml` measures one cell and one
line, once, so nothing measures them again its own way. `ui/Rail.qml` draws the
graph rail, so the log, the notifications and the bar popup cannot drift apart.

Every glyph the grid draws is declared in one place, `Model.GLYPHS`, because a
glyph the monospace font lacks falls back to another face at another width and
shears every line under it. `tests/glyph-test` asks fontconfig who serves each
one and fails if any answer is not the grid font — which is a thing counting
code points cannot catch, and did not.

## Tests

```bash
tests/run
```

Nine files. Nothing there touches dev-null.sh: `tests/mock-devnull` stands in
for it, so no test ever posts a real commit. The mock verifies the signatures
it is sent with `ssh-keygen -Y verify`, so a request that would be refused
upstream is refused here too.

`tests/glyph-test` is the odd one: it asks fontconfig, not node, because
whether a glyph is one cell wide is a question only the font can answer.

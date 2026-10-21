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

It follows the Omarchy theme for background, text and font, and uses
dev-null's own palette for the author lanes and the action blue.

![The log as a commit graph, with link cards and quotes](docs/screenshots/log.png)

| Notifications | A profile |
|---|---|
| ![Notifications on the rail, each with its icon](docs/screenshots/notifications.png) | ![A profile with its commits, followers and following](docs/screenshots/profile.png) |

## Install

```bash
git clone https://github.com/zangetsu02/omarchy-devnull ~/.config/omarchy/plugins/zangetsu.devnull
omarchy bar put zangetsu.devnull
```

So that the full client floats, centred and opaque, instead of joining the
tiling layout with the see-through default every window gets,
add this to `~/.config/hypr/hyprland.lua` and run `hyprctl reload`:

```lua
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { float = true, tag = "-default-opacity", opacity = "1 1" })
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { size = { "(min(1220, monitor_w*0.92))", "(min(800, monitor_h*0.85))" } })
o.window({ class = "^org.quickshell$", title = "^dev-null$" }, { center = true })
```

Size comes before centring, and the `min()` keeps it inside a small or
vertical monitor. Then pair this machine once, as below.

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
~/.config/omarchy/plugins/zangetsu.devnull/scripts/setup-devnull
```

It makes the key, registers a handler for `devnull://` links, opens the approval
page in your browser, and redeems the code that comes back. One minute, once.

Then, if you have never done it, **accept the commit rules on dev-null.sh**.
Until you do, the server refuses every reply — from here, from the app, from
anywhere.

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

**A reply can be held.** dev-null moderates commits from accounts without
"good reputation", so yours may come back pending. The panel says which; it
never pretends a held reply is live.

## When it breaks

The icon goes crossed after three refusals in a row from a device that is no
longer approved, and the panel tells you to run the setup again. A wrong clock
or a dead network look different on purpose: they say so, and they never send
you off to re-pair something that was never broken.

## Limits

`devnull://` is the official app's URL scheme, and pairing borrows its flow.
It works, your account is your own, but this is not a sanctioned third-party
API: if that flow ever closes, pairing stops working. Nothing else here depends
on it once the device is approved.

The site is weeks old and its API is undocumented. Shapes can change.

## How it is put together

| File | Role |
|---|---|
| `scripts/devnull` | The only thing that talks to dev-null.sh: signs each request, prints JSON. |
| `scripts/setup-devnull`, `scripts/devnull-callback` | Pairing, once. |
| `Model.js` | Pure functions: what to call when, how a commit becomes a row, the palette. |
| `Service.qml` | Runs the bridge and holds the log, threads and notifications. |
| `Pager.qml` | Any other paged list: starred, a profile's commits, followers. |
| `Panel.qml` | The bar icon and its popup. |
| `FullPanel.qml` | The full client: layout, keys, navigation, and the actions rows call. |
| `LogRow.qml`, `NoticeRow.qml`, `CommitPage.qml`, `ProfilePage.qml`, `Composer.qml`, `CommitList.qml` | Its pieces. |
| `CommitImages.qml`, `ImageViewer.qml` | A commit's pictures, and the full-size viewer. |
| `Picture.qml`, `Avatar.qml`, `ActionButton.qml`, `LinkText.qml`, `Mono.qml` | Shared building blocks. |

Rows and pages only talk to `FullPanel`; it is the one that knows the service.

## Tests

```bash
tests/run
```

Nothing there touches dev-null.sh: `tests/mock-devnull` stands in for it, so no
test ever posts a real commit.

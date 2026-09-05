# Presence

How Sabha decides what coloured dot appears beside a person's name — what they
chose, checked against whether they're reachable — and who that change is
delivered to.

This is the *presence* layer. It is deliberately **not** the connection layer:
`Membership::Connectable` still owns `connected_at`, the "N here now" count, push
gating, and email-away logic, and none of that reads presence. The two answer
different questions and are allowed to disagree — see
[Where the two signals diverge](#where-the-two-signals-diverge).

For what a Do Not Disturb dot does *not* do, see
[`NOTIFICATIONS.md`](NOTIFICATIONS.md).

---

## Vocabulary

A few words circle the same idea; each has exactly one job here, and the code
sticks to them.

| Word | Means | Lives in |
|---|---|---|
| **Active** | you're here and engaged — the green presence state and its dot | the `:active` dot token, and the "Active" label the picker shows |
| **Availability** | the *dimension* you set: Active / Away / Do Not Disturb / Invisible | the `availability` enum. Its stored value for "Active" is `available` — a storage name only, kept because renaming it would collide with `status.active?` |
| **Idle / Away / Do Not Disturb / Invisible / Offline** | the other resolved dots | `presence_dot` return tokens |
| **Interaction** | a human touched a tab recently (the idle watcher) | `interacted_recently?`, `last_active_at`, `ACTIVE_WINDOW` |
| **Connected** | reachable — a live socket with a fresh `connected_at` | `Membership.connected`, `connected?`, `connected_member?` |
| **Here now** | how many members are *connected* right now (workspace vitality) | `Membership.connected_member_count`, `AccountsHelper#here_now_count`, the header text |

The word **"online" is not used** — reachability is *connected*, and its count is
*here now*.

---

## The two inputs

| Input | Stored as | Set by | Means |
|---|---|---|---|
| **Availability** | `users.availability` enum (`available` / `away` / `do_not_disturb` / `invisible`), default `available` | the profile-flyout picker | "here's how I want to appear" |
| **Activity** | `users.last_active_at` | the idle watcher, throttled | "a human touched this tab recently" |
| **Reachability** | `memberships.connected_at` (existing) | the room heartbeat | "a tab is open on a room" |

The column is called `availability`, not `presence`, because an attribute named
`presence` shadows `Object#presence` on every `User` instance. Availability is
what you chose; presence is what it resolves to.

---

## The resolver

One method folds all three into a token. Order encodes the product rules:

```ruby
# app/models/user/presence.rb
def presence_dot(connected:, active:)
  return nil if deactivated? || banned?   # no claim at all
  return :offline if invisible?           # you chose to look gone — aims down
  return :offline unless connected        # unreachable outranks intent
  return :dnd if do_not_disturb?          # a claim outranks inferred idleness
  return :away if away?

  active ? :active : :idle                # only "available" is second-guessed
end
```

Three consequences worth knowing:

- **Nobody can fake presence upward.** `offline` sits above the manual value, so
  you can only ever make yourself look *less* available than you are.
- **`invisible` is the far end of that same rule** — the one state that aims the
  dot *down* to `offline` outright, past even reachability, so a connected person
  can look gone. It's the appear-offline lever. Everyone else sees `:offline`;
  only the person themselves sees a distinct `:invisible` dot (a hollow ring), so
  they stay reminded they're hidden rather than mistaking it for a dead socket.
  See [`own_presence_dot`](#reading-it).
- **`idle` and `away` render identically** (the amber dot). The difference
  between "I said I'm away" and "you stopped typing" is ours to act on, not
  something a reader of the dot needs to arbitrate.

`nil` means *render nothing* — a deactivated or banned person's status chip is
the only claim made about them.

### Reading it

| Call | Use |
|---|---|
| `user.presence_dot_now` | one user, 0–1 queries — the reachability lookup is skipped when they're already active |
| `User.presence_dots_for(users)` | a whole list, two queries total — use this in any loop |
| `user.own_presence_dot` | what *you* see on your own avatar: `connected: true, active: true`, so your manual choice speaks for itself |

---

## Idleness

Idle is inferred client-side and reported as **edges only**, never as a stream.

```
idle_controller.js  ──▶  HeartbeatChannel#activity  ──▶  User#interacted
   (on <body>)                                     └──▶  User#went_idle
```

| Constant | Value | Why |
|---|---|---|
| `IDLE_AFTER` (JS) | 10 min | mirrors `ACTIVE_WINDOW` so client and server agree where the line is |
| `ACTIVE_REPORT_INTERVAL` (JS) | 2 min | a busy page fires interaction constantly; anything tighter is pure RPC |
| `TIMER_RESOLUTION` (JS) | 5 s | `pointermove` alone fires ~100×/s; the idle clock is only pushed forward this often |
| `ACTIVE_WINDOW` | 10 min | `Membership::Connectable::ACTIVITY_TIERS[:active]` |
| `ACTIVITY_REFRESH_THRESHOLD` | 3 min | only rewrite `last_active_at` once it's this stale — every write lands on the same single SQLite writer the chat uses |

`went_idle` **ages the timestamp out** rather than clearing it
(`last_active_at = ACTIVE_WINDOW.ago - 1.second`), so a tab that dies without
ever reporting still goes idle on its own instead of staying green forever.

It's **refused while activity was just reported** (`reported_recently?`, the same
freshness the write path throttles on): you can't be idle inside the window you
just proved you were active in. Because presence rides one shared column, this is
what stops a second tab going quiet from backdating the timestamp out from under a
tab that's actively reporting — and stops an authenticated client forging
alternating idle/active edges to force a write and a fan-out on every message. A
live tab keeps the column fresh, and nothing can age out what it's holding up. The
residual: two tabs can disagree for up to one report interval, after which the
active tab's next report settles it — a brief flicker, not a redesign into
per-tab tracking.

A hidden tab is not interaction: the watcher returns early unless
`document.visibilityState === "visible"`, or tabbing away would keep you looking
available indefinitely.

The gap this leaves: a tab parked on a **roomless** page long enough to go idle
reads as `offline` rather than `idle`, because the room heartbeat is the only
other reachability signal. That's the safe direction to be wrong in.

---

## Surfaces

A dot can appear in eight places. Each has an id (`presence_dot_<surface>_user_N`)
and a positioning class; five also print the state in words
(`presence_label_<surface>_user_N`).

| Surface | Where | Label? | Delivery group |
|---|---|---|---|
| `sidebar` | your own footer | yes | `own` |
| `direct` | sidebar DM row | — | `chrome` |
| `conversation` | DM inbox row | — | `chrome` |
| `nav` | room header | yes | `chrome` |
| `member` | members directory | yes | `rare` |
| `participant` | DM roster | yes | `rare` |
| `quick_profile` | hover card | — | none — fetched fresh on open |
| `profile_hero` | profile page | yes | `rare` |

The hover card is the one surface that draws a dot but is **never broadcast to**.
It's lazy-loaded and lives for seconds, rendering `presence_dot_now` fresh every
time it opens, so a live replacement target would only ever refresh a card that's
already gone. It's listed in `PresencesHelper::TRANSIENT_SURFACES`, and the
group-coverage test treats "delivered by one group" and "explicitly transient" as
the only two valid states for a surface.

Labels are replayed alongside their dot. A dot that turns amber next to words
still reading "Active" is worse than one that never moved.

The picker's swatches are **not** `.status-dot`. The picker shows intent, never
resolved state, so it has its own `.sidebar__presence-dot` — which also keeps it
out of the surface-sizing cascade.

---

## Delivery

Delivery follows the audience, not the headcount. Up to three sends per change:

```ruby
# app/models/user/presence.rb
broadcast_dots_to self, "own", dot                       # → [self, :presence]
broadcast_dots_to_each presence_audience, "chrome", dot  # → each partner's [user, :presence]
broadcast_dots_to Current.account, "rare", dot if rare   # → [account, :presence]
```

| Group | Payload | Goes to | Subscribed by |
|---|---|---|---|
| `own` | 444 B · 2 actions | you | the layout |
| `chrome` | 952 B · 4 actions | your DM partners (`presence_audience`) | the layout |
| `rare` | 1,286 B · 6 actions | the workspace stream | only the directory, profile, and roster pages, while open |

**`rare` is only sent for a declared change.** An ambient active/idle flicker —
the high-frequency path — reaches `own` and `chrome` but skips `rare` (`rare:
false` on the idle verbs). That payload is the one that almost always reaches
nobody, so it's the one render almost always thrown away; not paying it on every
mouse-goes-still edge is the point. A directory or profile is worth a live update
for someone declaring "Away", not for their pointer pausing — and those pages are
correct on load either way. Only `change_availability!` sends all three.

The payload carries only the subject's own dots, so every partner receives
byte-identical HTML. It is rendered **once** and the same string is published to
each — `broadcast_render_to` renders per call, which is why it isn't used here,
and why a test asserts the chrome payload renders exactly once regardless of how
many partners exist.

**Every viewer subscribes to their own stream**, in the layout:

```erb
<%= turbo_stream_from Current.user, :presence %>
```

A per-*subject* subscription (one beside each visible avatar) would subscribe the
same person twice on any page where they appear in both the sidebar frame and the
main document. That is **wasteful, not fatal** — worth stating plainly, because
this codebase previously recorded it as fatal:

- the server ignores a repeated subscribe (`return if subscriptions.key?(id_key)`),
  so no second confirmation is sent
- the client's `confirmSubscription(identifier)` forgets **every** subscription
  sharing that identifier (`findAll`), so the guarantor stops retrying all of them
- `remove` likewise only sends `unsubscribe` once the last one is gone

Measured on a room page carrying three identical `HeartbeatChannel` subscriptions:
zero WebSocket frames in a five-second idle window. No retry storm.

What duplicates actually cost is an extra subscribe command per navigation and a
second element to keep in sync. Keying by viewer makes one-subscription-per-page
structural rather than a convention to remember.
`test/system/presence_test.rb` guards it.

Pages drawing the rarer surfaces add `turbo_stream_from Current.account, :presence`
themselves, so that payload costs only what someone is actually looking at. A
publish to a stream with no subscribers is a hash lookup in the in-memory broker.

Every surface belongs to exactly one group (`PresencesHelper::SURFACE_GROUPS`).
A surface in no group would silently never be delivered, so
`test/helpers/presences_helper_test.rb` asserts the groups cover the surfaces
exactly — adding a ninth fails until it's been given an audience.

### When nothing is sent

All three verbs end on one rule — do the write, then compare the **resolved dot**,
never the stored value:

```ruby
def broadcasting_dot_change(rare: true)   # the idle verbs pass rare: false
  was = presence_dot_now
  yield
  now = presence_dot_now

  broadcast_presence now, rare: rare unless now == was
end
```

Comparing the resolved dot is what makes idleness free for anyone who has already
said something about themselves. Away and Do Not Disturb sit above the
active/idle distinction, so those tabs going quiet and coming back changes
nothing anyone can see, and says nothing. Since idle edges dominate presence
traffic, that removes most of it for those people.

Re-picking the state you already hold is silent for the same reason — but note it
isn't *always* a no-op, because choosing also counts as activity and that alone
can lift you off idle.

---

## What it costs

Counted from the code paths, not estimated.

| Path | Cost |
|---|---|
| One person's dot | **0–1 queries** — `last_active_at` is on the record; the reachability check is skipped when they're active |
| A list of dots | **2 queries, flat** — `presence_dots_for`, whatever the length |
| Rendering a page | **0** — the stream tags are markup; subscribing touches no database |
| An activity report | arrives every 2 min over the existing socket; writes only once the watermark is 3 min stale, so roughly **one UPDATE per 4 min per active person** |
| An idle broadcast | **1 query** for the audience, **2 renders** (own + chrome, flat), **K+1** broker publishes — the frequent path |
| A declared broadcast | **1 query** for the audience, **3 renders** (flat), **K+2** broker publishes — only on a picker change |

The write is a bare `update_columns`: no callbacks, no validations, no
`updated_at` bump — so nothing keyed on the user's timestamp is invalidated by
someone moving their mouse. That matters because every write lands on the same
single SQLite writer the chat itself uses; `ACTIVITY_REFRESH_THRESHOLD` is the
dial to turn if it's ever felt, and the only cost of raising it is noticing
idleness slightly later.

The write throttle is not an RPC throttle, though. The idle watcher doesn't open a
channel of its own — it rides the `HeartbeatChannel` that connection-status and
room-refresh already hold app-wide, adding an `activity` action rather than a
second socket. But every `activity` report still invokes that action over an
`anycable-go`→Rails RPC round-trip, including the majority that the watermark check
turns into no writes. The throttle spares the SQLite writer, not the RPC path; that
round-trip is the price of resolving idleness on the server (a turbo stream is
broadcast-only and can't receive), which is what lets *other* viewers' dots, the
directory sort, and the broadcasts reflect your idleness at all.
`ACTIVE_REPORT_INTERVAL` (the client's 2-minute report cadence) is the dial that
bounds the RPC volume.

Storage is two columns and **no index** — nothing sorts or filters by either, so
an index would be write cost for nothing.

On the client: five passive listeners plus `visibilitychange`, with timer churn
bounded to one clear/set per 5 seconds however fast the pointer moves.
`HeartbeatChannel` is subscribed three times per page (connection status, room
refresh, idle watcher), costing two redundant subscribe commands per navigation —
see the note above on why that's waste rather than a leak.

---

## Where the two signals diverge

The workspace header reads `here_now_count`, which is
`Membership.connected_member_count` — pure connection data, untouched by this
feature. So the two can visibly disagree: someone on Do Not Disturb is **counted
in "here now" while showing a red dot**.

That divergence is intentional, not a bug. "Here now" is a workspace-vitality
signal — *is anyone around* — while the dot answers whether a person is *open to
being interrupted*. They are two different questions, so they are allowed to
disagree. The count is **fully availability-blind**: it counts everyone with a
fresh socket regardless of what they chose, so a Do Not Disturb *and even an
invisible* member is still counted, exactly as an idle member is. Invisible hides
you from the *dots* — the thing that names you — not from the vitality number,
which names no one. `AccountsHelper#here_now_label` gives the count a tooltip
("Members connected in the last 10 minutes") so a reader doesn't pit the number
against a nearby dot.

Room info does not display member lists or room attendance. Members and room
management live in Room settings; the contextual panel keeps its description
and controls, leaving space for future huddles. It performs no roster queries
or presence refreshes. See `docs/plans/2026-09-05-001-feat-room-info-panel-plan.md`.

---

## Key files

| File | Role |
|---|---|
| `app/models/user/presence.rb` | resolver, verbs, audience, delivery |
| `app/helpers/presences_helper.rb` | dot classes, labels, surfaces, delivery groups |
| `app/javascript/controllers/idle_controller.js` | client-side idle edges |
| `app/channels/heartbeat_channel.rb` | `activity` action — rides the existing per-user channel, not `PresenceChannel` (which is room-bound and would stop hearing from anyone reading their settings) |
| `app/controllers/users/presences_controller.rb` | `PATCH` the signed-in user's own presence; the route carries no id to spoof |
| `app/views/users/presences/` | `_dots` plus the three audience wrappers |
| `app/views/users/sidebars/_profile_menu.html.erb` | the picker |

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

## The two inputs

| Input | Stored as | Set by | Means |
|---|---|---|---|
| **Availability** | `users.availability` enum (`available` / `away` / `do_not_disturb`), default `available` | the profile-flyout picker | "here's how I want to appear" |
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
  return :offline unless connected        # unreachable outranks intent
  return :dnd if do_not_disturb?          # a claim outranks inferred idleness
  return :away if away?

  active ? :active : :idle                # only "available" is second-guessed
end
```

Two consequences worth knowing:

- **Nobody can fake presence upward.** `offline` sits above the manual value, so
  you can only ever make yourself look *less* available than you are.
- **`idle` and `away` render identically** (the amber dot). The difference
  between "I said I'm away" and "you stopped typing" is ours to act on, not
  something a reader of the dot needs to arbitrate.

`nil` means *render nothing* — a deactivated or banned person's status chip is
the only claim made about them.

### Reading it

| Call | Use |
|---|---|
| `user.presence_dot_now` | one user, two queries |
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
| `quick_profile` | hover card | — | `rare` |
| `profile_hero` | profile page | yes | `rare` |

Labels are replayed alongside their dot. A dot that turns amber next to words
still reading "Available" is worse than one that never moved.

The picker's swatches are **not** `.status-dot`. The picker shows intent, never
resolved state, so it has its own `.sidebar__presence-dot` — which also keeps it
out of the surface-sizing cascade.

---

## Delivery

Delivery follows the audience, not the headcount. Three sends per change:

```ruby
# app/models/user/presence.rb
broadcast_dots_to self,            "own",    dot   # → [self, :presence]
presence_audience.each { |viewer| broadcast_dots_to viewer, "chrome", dot }
broadcast_dots_to Current.account, "rare",   dot   # → [account, :presence]
```

| Group | Payload | Goes to | Subscribed by |
|---|---|---|---|
| `own` | 444 B · 2 actions | you | the layout |
| `chrome` | 952 B · 4 actions | your DM partners (`presence_audience`) | the layout |
| `rare` | 1,537 B · 7 actions | the workspace stream | only the directory, profile, and roster pages, while open |

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

All three verbs broadcast only when the dot other people see actually moved:

- `interacted` — silent unless it moves you off idle; most reports write nothing
- `went_idle` — silent if you were already idle
- `change_availability!` — compares the **resolved dot**, not the stored value,
  because choosing also counts as activity and that alone can lift you off idle

---

## Where the two signals diverge

The workspace header still reads `online_users_count`, which is
`Membership.online_user_count` — pure connection data, untouched by this feature.
So the two can visibly disagree: someone on Do Not Disturb is **counted in "here
now" while showing a red dot**.

That's a known, unresolved product question rather than a bug: whether a roster
dot answers *"is their client connected?"* or *"are they open to being
interrupted?"*. Only one can own the dot.

Room rosters are also deliberately **not** live — extending presence there would
reintroduce the large fan-out this design removes, since a room can hold
everyone. They're correct on load.

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

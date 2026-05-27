---
title: Room Type Fan-Out Polymorphism
type: refactor
status: proposed
date: 2026-05-27
revised: 2026-05-27
---

# Room Type Fan-Out Polymorphism

## Summary

Finish the room-type polymorphism pattern that `app/models/room.rb:84` already endorses ("Subclasses override to encode room-type fan-out so callers don't branch on `room.is_a?(Rooms::Direct)`"). Three methods on `Room` base still have multi-branch logic that belongs in subclasses: `display_name`, `bot_memberships_for_events`, and `ensure_visible_members_remain!`. Predicates (`direct?`, `thread?`, `open?`, `closed?`) stay — they're cheap and used by view code.

## Scope

**In scope:**
- `Room#display_name(for_user:)` (`room.rb:269-278`) — three-way branch → subclass overrides
- `Room#bot_memberships_for_events(item, event)` (`room.rb:251-267`) — branches on `direct? || thread?` → per-subclass methods backed by a `Membership` scope
- `Room#ensure_visible_members_remain!(excluding:)` (`room.rb:240-244`) — `return if open?` → no-op override on `Rooms::Open`

**Explicitly out of scope:**
- Removing predicate methods (`direct?`, `thread?`, `open?`, `closed?`) — they're fine for view branching
- `Room#sidebar_room?` (`room.rb:121-123`) — `open? || closed?` predicate composition. Borderline, but it's used in views and reads cleanly. Leave for now.
- Extracting a shared `Rooms::AllMembers` parent for Open/Closed — adds a class for one bit of difference
- `Message#ensure_everyone_mention_allowed`'s single `room.is_a?(Rooms::Open)` check — one adapter, hypothetical seam, fine as-is
- `Rooms::Thread#applicable_activity_types`'s `parent_room&.direct?` peek — that's polymorphism on a different room, not on `self`

## Design

### `display_name`

- Base `Room#display_name(for_user: nil)` returns `name` so callers can polymorphically dispatch without `is_a?` checks
- `Rooms::Direct` overrides → roster of users excluding `for_user`
- `Rooms::Thread` overrides → `"🧵 #{parent_message.room.name}"`
- `Rooms::Open` and `Rooms::Closed` inherit base default

The `for_user:` kwarg stays on the base signature for stable polymorphic dispatch even though only Direct uses it. Subclasses keep `for_user:` in their signature (not `_for_user:`) — signature stability beats Rubocop's unused-kwarg lint here.

### `bot_memberships_for_events`

The query that finds eligible bot memberships is about `Membership`, not `Room`. Lift it to a `Membership` scope, then let each subclass own its `bot_memberships_for_events` method outright. Each method reads top-to-bottom without holding a parent class in your head.

```ruby
# app/models/membership.rb
scope :eligible_for_bot_events, -> {
  active.where(involvement: [ :mentions, :everything ])
    .joins(:user).merge(User.active_bots)
    .includes(user: :webhook)
}
```

```ruby
# app/models/rooms/direct.rb  and  app/models/rooms/thread.rb
def bot_memberships_for_events(_item, _event)
  memberships.eligible_for_bot_events.to_a
end
```

```ruby
# app/models/rooms/open.rb  and  app/models/rooms/closed.rb
def bot_memberships_for_events(item, event)
  eligible = memberships.eligible_for_bot_events
  return eligible.to_a unless item.is_a?(Message) && event == :created
  eligible.select { |m| item.mentionees.include?(m.user) || item.mentions_everyone? }
end
```

`Room#bot_memberships_for_events` is removed from the base class entirely. The `Membership` scope eliminates the SQL duplication between Open and Closed.

### `ensure_visible_members_remain!`

Currently:

```ruby
# app/models/room.rb:240-244
def ensure_visible_members_remain!(excluding:)
  return if open?
  remaining = memberships.visible.where.not(user_id: Array(excluding)).count
  raise Membership::LastVisibleMemberError if remaining <= 0
end
```

Move the `open?` short-circuit into a no-op override on `Rooms::Open`:

```ruby
# app/models/room.rb (base)
def ensure_visible_members_remain!(excluding:)
  remaining = memberships.visible.where.not(user_id: Array(excluding)).count
  raise Membership::LastVisibleMemberError if remaining <= 0
end

# app/models/rooms/open.rb
def ensure_visible_members_remain!(excluding:)
  # open rooms have no visibility constraint
end
```

### Rejected shapes (recorded so they don't get re-suggested)

- **Template-method split** (base owns SQL + virtual `filter_eligible_bots`, subclasses override the filter). Reads like GoF Template Method transplanted into Rails. Bouncing between base and subclass to understand a single call. Private-or-protected override hooks accumulate over time. The DHH-style alternative is what's now proposed: each subclass owns its own method top-to-bottom, queries live as scopes on the model whose columns they touch.
- **Extract `Rooms::AllMembers` parent class** for Open/Closed — adds a class for one bit of difference (`@everyone` handling). Cost > benefit.
- **Invert the default** (base does filtering, Direct/Thread override to skip) — moot once the method moves into each subclass.

## Implementation steps

1. **`app/models/membership.rb`** — add `eligible_for_bot_events` scope.
2. **`app/models/room.rb`** — remove `bot_memberships_for_events` entirely; remove `open?` short-circuit from `ensure_visible_members_remain!`; replace `display_name` body with `name`.
3. **`app/models/rooms/direct.rb`** — add `display_name(for_user: nil)` override; add `bot_memberships_for_events(_item, _event)` returning `memberships.eligible_for_bot_events.to_a`.
4. **`app/models/rooms/thread.rb`** — add `display_name(for_user: nil)` override; add the same `bot_memberships_for_events` override as Direct.
5. **`app/models/rooms/open.rb`** — add `bot_memberships_for_events(item, event)` with mention-filter; add no-op `ensure_visible_members_remain!(excluding:)`.
6. **`app/models/rooms/closed.rb`** — add `bot_memberships_for_events(item, event)` with mention-filter.

## Verification

Existing tests are protective — behavior-asserted through the `Room` interface, not implementation-coupled:

- `test/models/room_test.rb:311-367` — five `bot_memberships_for_events` tests (created, updated, muted, no-webhook, thread)
- `test/models/rooms/direct_group_test.rb:35-53` — Direct's `display_name(for_user:)`
- `test/models/rooms/thread_test.rb:38` — Thread's `display_name`
- `test/models/room/message_pusher_test.rb:4-13` — Open/Closed `display_name` (push payload title)
- Any test covering `ensure_visible_members_remain!` (search `test/models/`) — `Membership::LastVisibleMemberError` raises should still trigger for non-Open rooms

**Required new tests (not optional):**

- **Direct-room-bot event test** mirroring `room_test.rb:352-367` (the thread case). Asserts a bot in a DM receives message events without requiring a mention. Locks in the permissive default for Direct so a future "simplification" doesn't regress it.
- **`Membership.eligible_for_bot_events` scope test.** Independent of room type — exercises the scope's filter (active, involvement, joined active bots, webhook preload) directly. The scope is now a unit worth its own coverage.

**Run:**

```sh
bin/rails test test/models/room_test.rb test/models/rooms/ test/models/room/ test/models/membership_test.rb
SAAS=true bin/rails test saas/test/   # same code paths run in SaaS
```

## Notes

- No `CONTEXT.md` term added — refactor uses existing vocabulary (Room, Direct, Thread, Open, Closed, Membership).
- Pattern precedent in the codebase: `applicable_activity_types` and `default_involvement` already follow this shape. This plan finishes the pattern, doesn't introduce it.
- Captured from `/improve-codebase-architecture` review on 2026-05-27. Candidates 1 and 2 from that review (Session unification, OTP unification) were rejected and recorded as `docs/adr/0001-tenancy-boundary-is-an-architectural-seam.md`.
- Revised 2026-05-27 after DHH-style review pushback: original draft used a template-method split (base + virtual filter hook). The reframe moves the SQL to a `Membership` scope, which eliminates the duplication argument that justified the template-method shape, and lets each subclass own its method outright. Also added `ensure_visible_members_remain!` to scope after the review surfaced it.

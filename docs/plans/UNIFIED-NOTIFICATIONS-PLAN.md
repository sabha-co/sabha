# Unified notification configuration

**Status:** Proposed (2026-05-08).
**Area:** Notification routing (push, email, in-app) + user preferences.
**Scope:** Replace today's split decision logic (push in `Room::MessagePusher`, in-app in `Message` callbacks, email nowhere) with one dispatcher and one settings panel. Reintroduce email — mention + DM only, when away — under a feature flag. Add manual snooze.

## Why

Three notification surfaces exist, each with a different decision tree:

- **Push** lives in `app/models/room/message_pusher.rb`. Honors `Membership#involvement` and per-membership `disconnected` (60s TTL). Works.
- **In-app** lives in a `Message` after-create callback. Creates `Notification` rows for every mentionee regardless of involvement — out of sync with push.
- **Email** does not exist. The old `mailkick_subscriptions` table and `memberships.notified_until` column were dropped in `db/migrate/20260214163011_remove_mailkick_and_email_notifications.rb`. We're now reintroducing email deliberately.

There is no global user preference. No DND, no snooze, no "email me when I'm away", no global mode. `users.preferences` is declared as a JSON column (`app/models/user.rb:7`) but unused — v1 introduces a dedicated `user_notification_settings` table instead (Fizzy parity).

We want the Slack/Discord shape, opinionated for Sabha:

- A **coarse global mode** per user — `all` / `mentions_and_dms` / `nothing` — that mirrors the `Membership#involvement` mental model.
- The **existing per-room override** stays.
- **Manual snooze** (1h / 4h / until tomorrow / indefinite) — suppresses push and email, leaves in-app rows so the Activity tab still tells the truth on return.
- **Email v1**: mention + DM only, sent only when the user is away across the whole app, under a feature flag, defaulting to `never` for existing users.
- **Block suppression** for all three channels (push, email, in-app) — closes the harassment vector that today's block model only half-covers.

Outcome: one place decides what fires per recipient per event; one settings panel surfaces the controls; email is dark-shipped behind a flag and turned on per account.

## Architecture

### Routing

```
Room#receive(message)
  └→ Notification::DispatchJob.perform_later(message, activity_type, actor)
        └→ message.notify_recipients(activity_type, actor: actor)
              └→ for each candidate Membership:
                    membership.deliver_notification(message, activity_type, actor: actor)
                       ├→ create Notification row + broadcast  (when membership.receives_in_app_row_for?)
                       ├→ Notification::Channel::Push          (when membership.receives_push_for?)
                       └→ Notification::EmailJob.perform_later (when membership.receives_email_for?)
```

`activity_type` is a symbol — `:mention`, `:direct_message`, `:everyone_room_message`, `:thread_reply`, `:boost`. **Two of these are dispatcher-only** event types and never produce a `Notification` row: `:direct_message` (push + email channels only — DMs don't create in-app notifications) and `:everyone_room_message` (push channel only). The other three (`:mention`, `:thread_reply`, `:boost`) match the values already stored on `notifications.activity_type` and already in `Notification`'s inclusion validator at `app/models/notification.rb:25`. So **`Notification#validates :activity_type` does NOT change in v1** — the persisted vocabulary stays `%w[mention boost thread_reply]`. The dispatcher's symbol vocabulary is a strict superset used only at routing time. The dispatcher and channels case-switch on the symbol; no parallel class hierarchy.

This matches Fizzy's shape: Fizzy's `Notification::Pushable` does not have an Event class hierarchy either. Its `payload_type` resolves via `source_type.presence_in(%w[ Event Mention ]) || "Default"` — a string lookup at the boundary, not subclass dispatch. Earlier drafts of this plan proposed `Notification::Event::{Mention,DirectMessage,EveryoneRoomMessage,ThreadReply,Boost}` subclasses; dropped because every "subclass override" reduced to either a constant lookup (`IN_APP_ROW_TYPES`, `EMAIL_TYPES`) or a one-line recipient query that already exists on `Message`.

**Activity types and channels they fire on** — high-level routing only. For per-channel recipient queries (which differ across push / row / email for several types), see the **Per-channel recipient resolution** table below — that table is authoritative for delivery-time recipient sets.

| `activity_type` | Channels (v1) |
|---|---|
| `:mention` | in-app row, push, email |
| `:direct_message` | push, email |
| `:everyone_room_message` | push |
| `:thread_reply` | in-app row, push |
| `:boost` | in-app row |

**Mention recipient query, expanded** — preserves today's disjointness with the everyone-room set:

```ruby
def mention_recipients(message)
  base_user_ids = message.mentions_everyone? ? message.room.user_ids : message.mentionee_ids
  Membership
    .where(room_id: message.room_id, user_id: base_user_ids - [message.creator_id])
    .involved_in_mentions
    .pluck(:user_id)
end
```

**Disjointness invariant** (load-bearing — don't drop the involvement filter): a user has exactly one `Membership#involvement` value per room. `Membership.involved_in_mentions` and `Membership.involved_in_everything` are mutually exclusive scopes. So a user with `:everything` involvement who is `@everyone`-mentioned in a room **lands in `:everyone_room_message` only**, never in `:mention` — they get one push, not two. This mirrors `Room::MessagePusher` exactly today (`app/models/room/message_pusher.rb:50-63`), where `merge(Membership.involved_in_everything)` and `merge(Membership.involved_in_mentions)` carve disjoint subscription sets.

If we ever want a user with `:everything` to also receive `:mention`-channel email/in-app on top of push, that's a deliberate channel-routing decision, not an accident of recipient overlap. Today's behavior is "one signal per (user, message)"; v1 preserves that.

**Per-channel recipient resolution** (authoritative for delivery-time recipient sets) — today's row and push recipient sets diverge from each other for several activity_types. `Message#create_mention_notifications` creates rows for **all** mentionees (regardless of involvement), while `Room::MessagePusher` pushes only to involvement-filtered subsets. v1 preserves these row/push/email recipient sets; `Message#notify_recipients` resolves the candidate set per channel, then asks each candidate `Membership` whether it qualifies for that channel via the predicates on `Membership::Notifiable`. **Unread counters stay on the existing synchronous `Message#increment_unread_notifications_counters` path in v1 and move to the dispatcher no earlier than v1.2** (see Unread counter scope below).

| activity_type | Push recipients | Row recipients | Email recipients |
|---|---|---|---|
| `:mention` | `mentionees ∩ involved_in_mentions` | `mentionees - creator` (broader) — branch on `mentions_everyone?`: `room.user_ids - creator` for `@everyone`, else `mentionee_ids - creator` | same as Row (broader; reaches `:everything` mentionees too) |
| `:everyone_room_message` | `involved_in_everything` | none | none |
| `:direct_message` | `room.user_ids - creator` | none | `room.user_ids - creator` |
| `:thread_reply` | `(thread + parent_everything).uniq - creator - mentioned`, skip when `parent_room.direct?` | same as push | none |
| `:boost` | none | `[boosts.last.message.creator_id]` | none |

This is the single most load-bearing correction over earlier drafts: collapsing row and push recipients into one would silently shrink today's Activity-tab coverage (e.g. `@everyone` creates rows for every non-creator member today, not just the users whose per-room involvement qualifies for push). Counter recipient unification is deliberately deferred to v1.2 because badges have their own persisted counter, read-state, deletion, reactivation, and live-broadcast invariants.

**`:mention` row recipients must branch on `mentions_everyone?`** (load-bearing — don't drop the branch): for `@everyone` posts in non-DM rooms, today's `Message#create_mention_notifications` creates rows for `room.user_ids - creator` (`app/models/message.rb:267-271`), **not** just named mentionees. Under v1, an `@everyone` post in a 50-member room with no named mentions must still create 49 in-app rows. A naive `mentionee_ids - creator` query would create zero — silent regression in `@everyone` Activity-tab coverage.

Constants on `Membership::Notifiable`:

```ruby
ACTIVITY_TYPES      = %i[mention direct_message everyone_room_message thread_reply boost].freeze
IN_APP_ROW_TYPES    = %i[mention thread_reply boost].freeze                       # creates Notification rows + broadcasts
EMAIL_TYPES         = %i[mention direct_message].freeze
```

These constants drive the per-activity-type predicates on `Membership::Notifiable` — `receives_in_app_row_for?`, `receives_push_for?`, `receives_email_for?` — each a constant lookup combined with the per-recipient gates (block/banned/active/`receives?`/snooze/etc.). Unread-counter predicates are intentionally absent in v1; `Membership#unread_notifications_count` stays owned by the current message/read-state code until the v1.2 counter-specific migration.

**Push payload formatting** stays as-is in `Room::MessagePusher#build_payload` (today's `room.direct?` two-branch shape). Fizzy has a `Notification::DefaultPayload` / `EventPayload` / `MentionPayload` hierarchy because each type has substantively divergent rendering (`EventPayload` has a 60-line `case event.action` switch). Sabha's push copy doesn't diverge per activity type today — only by `room.direct?`. **Defer the Payload hierarchy until copy actually diverges per type**; when it does, mirror Fizzy's `Notification::*Payload` shape.

### Layering: global mode vs per-room involvement

Two layers, each with a distinct job. Reconciling them is the whole point of v1:

- **`Membership#involvement`** is the **delivery-time source of truth.** It says whether THIS room delivers `nothing`, only `mentions`, or `everything` for THIS user. Mirrors today's behavior exactly.
- **Global `prefs.mode`** is the **default for new memberships** and a **soft suppressor for outbound channels** (push + email) when set to `nothing`, **except per-room `:everything` overrides it**. A user who set room A to `:everything` keeps getting all-message push and email regardless of global mode. Snooze owns the master-kill-switch role (push + email suppressed regardless of involvement; indefinite snooze covers "permanent off"). Matches Slack: per-channel override wins at delivery; DND/snooze is the master kill switch.

Mode → default for new memberships:

| `prefs.mode` | New non-DM membership defaults to | DM membership |
|---|---|---|
| `nothing` | `invisible` | `everything` (DMs always loud) |
| `mentions_and_dms` (default) | `mentions` | `everything` |
| `all` | `everything` | `everything` |

**Wiring**: `Room#default_involvement(user:)` (currently hardcoded to `"mentions"` at `app/models/room.rb:125`) is updated to read from `user&.notification_settings&.default_involvement_for_new_membership`, falling back to `"mentions"` when there is no user (existing call sites pass `user: nil` for system grants). This is the seam the membership creation path already uses — `Room#memberships.grant_to` (`app/models/room.rb:6`) calls `room.default_involvement(user: user)` once per user being added. **`Rooms::Direct#default_involvement` is preserved verbatim** (`app/models/rooms/direct.rb:20`) so DMs always seed as `"everything"` regardless of global mode.

```ruby
# app/models/room.rb (modified)
def default_involvement(user: nil)
  user&.notification_settings&.default_involvement_for_new_membership || "mentions"
end

# app/models/rooms/direct.rb — unchanged
def default_involvement(user: nil)
  "everything"
end
```

When a user changes mode in the settings panel, the form offers **"Apply to all my rooms"** — **unchecked by default for every mode**, including `nothing`. Bulk-overwriting per-room overrides is destructive (silently blasts away any explicit `:everything` opt-ins), and the layering invariant is exactly that per-room intent dominates. Pre-checking on `nothing` would invert that invariant for the highest-blast-radius setting; the user must opt in to the bulk reset deliberately. The label includes a one-line consequence preview when checked: "This will overwrite involvement on N rooms (X currently set to all messages, Y to mentions only)." The bulk update calls `current_user.notification_settings.apply_to_all_rooms!`, which walks `user.memberships.visible.without_direct_rooms` and updates `involvement` to match the new default.

**`mode: "nothing"` is a soft suppressor, not a kill switch.** It seeds new memberships to `invisible` and suppresses push + email **for memberships that aren't `:everything`** — a per-room `:everything` override always wins, mirroring Slack's per-channel-override-vs-DND model. The master-kill-switch role is owned by snooze (push + email suppressed regardless of involvement). **In-app rows still get created** under `mode: nothing` so the Activity tab tells the truth on return — same as snooze. To stop in-app rows for a specific room, set that room's `involvement` to `:nothing` (per-room is the aggressive control).

### Unread counter scope

`Message#increment_unread_notifications_counters` (`app/models/message.rb:298`) remains unchanged in v1. It stays a synchronous `after_create_commit` callback that bumps `Membership#unread_notifications_count` for DMs, `@everyone` messages, and named mentions. This is deliberate: unread badges are not just another delivery channel. They are tied to `Membership#unread_at`, sidebar ordering, `UnreadNotificationsChannel`, soft-delete/hard-destroy decrement paths, reactivation repair, and DM sender edge cases. Moving them into the new dispatcher at the same time as push/email/in-app routing would make v1 harder to reason about and easier to regress.

Known tradeoff: today's counter path bypasses block checks and `Membership#receives?`, so a blocked or muted edge case can still bump a badge even when no in-app row, push, or email fires. v1 accepts that existing inconsistency to keep deploy behavior stable. v1.2 owns the counter-specific migration, with hard requirements to preserve synchronous-or-explicitly-tested timing, one-`update_all` performance, live badge broadcasts, deletion/rebalance/reactivation behavior, and the current DM sender edge case.

### Per-recipient decision tree

All gating predicates live on `Membership::Notifiable` — the gate logic is colocated with the record that owns the recipient state (`user`, `room`, `involvement`, presence). `Message#notify_recipients` and `User#email_*_notification` (the email-fire-time revalidation path) both call the same predicates, so the rules can't drift between initial dispatch and delayed delivery. No separate `Dispatcher` class, no `Decision` value object — predicates as questions on the Membership record, in the spirit of Fizzy's `Notification::Pushable` concern.

```ruby
# app/models/concerns/membership/notifiable.rb
module Membership::Notifiable
  extend ActiveSupport::Concern

  IN_APP_ROW_TYPES    = %i[mention thread_reply boost].freeze
  EMAIL_TYPES         = %i[mention direct_message].freeze

  def receives_in_app_row_for?(message, activity_type)
    notifiable_for?(message, activity_type) && IN_APP_ROW_TYPES.include?(activity_type)
  end

  def receives_push_for?(message, activity_type)
    return false unless notifiable_for?(message, activity_type)
    user.push_enabled? && !user.snoozed? && deliverable_outbound? && !connected?
  end

  def receives_email_for?(message, activity_type)
    return false unless notifiable_for?(message, activity_type) && EMAIL_TYPES.include?(activity_type)
    user.email_when_away? && deliverable_outbound? &&
      user.email_address.present? && user.verified? &&
      !user.banned? && !user.deactivated? &&
      user.workspace_locally_away? && Sabha.email_notifications?
  end

  private
    # Shared SKIP gates — common to every channel. If any of these fail,
    # the membership receives nothing for this (message, activity_type) pair.
    def notifiable_for?(message, activity_type)
      return false if user_id == message.creator_id && activity_type != :direct_message
      return false if user.bot? || !user.active?
      return false if user.blocked?(message.creator) || user.blocked_by?(message.creator)
      return false unless message.room.active? && message.active?
      active? && receives?(activity_type)
    end

    # Per-room :everything dominates global mode "nothing" — the user's
    # explicit per-room opt-in wins, matching Slack's per-channel-override-
    # vs-DND model. Snooze (above) owns the master-kill-switch role.
    def deliverable_outbound?
      user.notification_settings.mode != "nothing" || involved_in_everything?
    end
end
```

The `creator_id == user_id && activity_type != :direct_message` carve-out keeps the shared skip gate compatible with DM routing. DM candidate sets already subtract the creator for push and email in v1; unread-counter sender behavior stays in the existing `Message#increment_unread_notifications_counters` callback until v1.2.

`Message#notify_recipients(activity_type, actor: nil)` orchestrates the fan-out — it iterates candidate memberships and asks each the right predicates:

```ruby
# app/models/message.rb (added)
def notify_recipients(activity_type, actor: nil)
  actor ||= creator
  candidate_memberships(activity_type).each do |membership|
    membership.deliver_notification(self, activity_type, actor: actor)
  end
end

private
  def candidate_memberships(activity_type)
    user_ids = recipient_user_ids_for(activity_type)
    return [] if user_ids.empty?
    Membership.where(user_id: user_ids, room_id: room_id)
              .includes(user: :notification_settings)
  end
```

`Membership#deliver_notification` is the per-recipient fan-out:

```ruby
# app/models/membership.rb (added — alongside the Notifiable concern)
def deliver_notification(message, activity_type, actor:)
  if receives_in_app_row_for?(message, activity_type)
    Notification.create!(user: user, message: message, actor: actor, activity_type: activity_type.to_s)
  end
  Notification::Channel::Push.deliver(message, self) if receives_push_for?(message, activity_type)
  if receives_email_for?(message, activity_type)
    Notification::EmailJob.set(wait: Notification::EmailJob::EMAIL_GRACE_WINDOW)
                          .perform_later(user, message, activity_type)
  end
end
```

Note that `membership.receives?(activity_type)` is the only delivery-time gate that distinguishes mention events from everyone-room-message events — it's the today's-behavior gate, preserved verbatim. Global `mode` only suppresses when set to `nothing`; mentions/DMs/everyone-messages are not gated by mode otherwise.

**Preloading at dispatch top (perf — load-bearing for large rooms).** Each call into `Membership::Notifiable` predicates touches `user`, `notification_settings`, and (for some channels) block state. Without preloading, an `@everyone` post in a 1k-member room generates ~4k+ DB roundtrips. `Message#candidate_memberships` already eager-loads `user: :notification_settings`; the remaining preload is block state, fetched once per dispatch:

```ruby
# app/models/message.rb (added)
def notify_recipients(activity_type, actor: nil)
  actor ||= creator
  memberships = candidate_memberships(activity_type)
  return if memberships.empty?

  Block.preload_for!(creator_id, memberships.map(&:user_id))  # populates User#blocked? cache for the iteration
  memberships.each { |m| m.deliver_notification(self, activity_type, actor: actor) }
end
```

`Block.preload_for!` warms a thread-local cache that `User#blocked?`/`#blocked_by?` consult before falling back to a DB query — same pattern as `Current.set` for request-scoped state. Bounds dispatcher DB cost to **O(channels) per dispatch**, not O(recipients × gates). Revalidation at email-fire time inside `User#email_*_notification` skips the preload (single user, single membership — direct queries are fine).

**`Membership#receives?(activity_type)` truth table** — defensive second-line gate, consistent with the recipient queries above:

| activity_type | returns true when |
|---|---|
| `:mention` | `involvement.in?(%w[mentions everything])` (matches existing `receives_mentions?` at `app/models/membership.rb:110`) |
| `:direct_message` | `true` (DMs auto-seed `:everything`; `:nothing`/`:invisible` are never set on DM memberships) |
| `:everyone_room_message` | `involvement == "everything"` |
| `:thread_reply` | `involvement != "nothing" && involvement != "invisible"` (thread participants only — non-thread members are filtered upstream by the recipient query) |
| `:boost` | `true` (boost recipient is always the original creator) |

For `:mention`, `receives?` returning true for `:everything` members is **not a routing collision** — the `:mention` push recipient query subsets to mentionees and `:involved_in_mentions`, so `:everything` users are routed to `:everyone_room_message` push and never enter the `:mention` push set. `receives?` is the second-line-of-defense gate; the recipient queries are the primary disjointness mechanism.

Two presence checks:

- **Push** — per-membership `Membership#connected?` (room-scoped, current behavior preserved).
- **Email** — **workspace-locally** away check exposed as `User#workspace_locally_away?`, which queries `Membership.last_connected_at_for([id])` compared against `Membership::Connectable::ACTIVITY_TIERS[:active]` (10 minutes). User is "away for email" if they have no live connection in **this workspace's** memberships. **`Membership` is tenanted, so this query only sees presence within the tenant that fired the event** — a SaaS user heads-down in workspace B is treated as "away" by workspace A's dispatch. v1 ships with this workspace-local semantics deliberately: the alternative (querying `GlobalSession.last_active_at` from the untenanted DB for a true cross-workspace presence summary) is **deferred** because it crosses the tenant boundary and adds an untenanted-DB dependency to the hot dispatch path. Multi-workspace users may receive an email for a workspace A mention even while actively reading workspace B — accept the noise in v1, revisit if user complaints surface. **Checked twice**: once at event time inside `membership.receives_email_for?` (a live reader in *this workspace* gets nothing scheduled), and once again at fire time inside `EmailJob` via the same predicate. Both checks call the same `Membership::Notifiable` methods with the same `(message, activity_type)` pair.

The 5-minute grace window scheduled by `EmailJob.perform_later(wait: EMAIL_GRACE_WINDOW)` is the cancellation path. If the user reconnects during the window, the job no-ops at fire time. No active job cancellation needed.

`EMAIL_GRACE_WINDOW = 5.minutes` — chosen to match Slack's "as soon as possible" timing (~5–15 min) and avoid emailing users who just glanced at their phone. Tighter windows (60s) feel engineering-correct but produce noisy false positives for the common "stepped away from the keyboard" case. The cost of a 5-min delay on the rare genuinely-away mention is small; the user wasn't going to read the email for hours anyway.

## Data model

### `User::NotificationSettings` (real AR record)

Direct Fizzy parity — Fizzy's `User::Settings` (`fizzy/app/models/user/settings.rb`) is a real AR record on a `user_settings` table, not a JSON column. The reviewer's earlier `store_accessor`-on-`User` suggestion and the prior PORO-over-`users.preferences` shape were both rejected because v1 already needs the side-effect callbacks AR gives for free (snooze flips that should flush queued mail, mode flips that should bulk-update memberships, `email_when_away: false` flips that revalidate at fire time). Sabha's existing `users.preferences` JSON column is unused today — leave it for unrelated future prefs or drop it later.

```ruby
class User::NotificationSettings < ApplicationRecord
  # Use the repo's hash-mapped string-enum pattern (see app/models/membership.rb:35).
  # Array enum syntax stores integers; Sabha's convention is string columns mapped to themselves.
  enum :mode, %w[ nothing mentions_and_dms all ].index_by(&:itself), default: "mentions_and_dms", prefix: :mode

  belongs_to :user

  SNOOZE_PRESETS = %w[ 1h 4h until_tomorrow indefinite ].freeze

  def snoozed?
    snooze_indefinite? || (snooze_until.present? && snooze_until > Time.current)
  end

  def snooze!(preset)
    case preset
    when "indefinite" then update!(snooze_indefinite: true,  snooze_until: nil)
    else                   update!(snooze_indefinite: false, snooze_until: resolve_snooze(preset))
    end
  end

  def unsnooze!
    update!(snooze_indefinite: false, snooze_until: nil)
  end

  # Maps the global mode to the involvement that NEW non-DM memberships should default to.
  # `Rooms::Direct#default_involvement` always returns "everything" and is preserved verbatim
  # — DMs are never seeded from the global mode (see app/models/rooms/direct.rb:20).
  def default_involvement_for_new_membership
    case mode
    when "nothing"           then "invisible"
    when "mentions_and_dms"  then "mentions"
    when "all"               then "everything"
    end
  end

  # Bulk-applies the user's current mode to all their visible non-DM memberships.
  # Owned by the settings record (which owns the `mode` source-of-truth), not by
  # `User`, so the call site reads `user.notification_settings.apply_to_all_rooms!`.
  def apply_to_all_rooms!
    user.memberships.visible.without_direct_rooms.update_all(involvement: default_involvement_for_new_membership)
  end

  # Per-toggle verbs — each preference toggle is its own create/destroy on a
  # noun resource (see Settings UI § routes), and each maps to one of these
  # bang verbs. Verbs over generic setters; reads naturally at the call site.
  def email_when_away_on!  = update!(email_when_away: true)
  def email_when_away_off! = update!(email_when_away: false)
  def push_enabled_on!     = update!(push_enabled: true)
  def push_enabled_off!    = update!(push_enabled: false)

  private
    def resolve_snooze(preset)
      case preset
      when "1h"             then 1.hour.from_now
      when "4h"             then 4.hours.from_now
      when "until_tomorrow" then Time.zone.now.tomorrow.beginning_of_day + 8.hours
      end
    end
end
```

`mode` is a real Rails enum mapped via the repo's `%w[...].index_by(&:itself)` pattern (matches `Membership#involvement` at `app/models/membership.rb:35`). Three values load-bearing for the default-involvement mapping. Bang methods (`mode_nothing!`) and predicates (`mode_nothing?`) come for free with the `prefix: :mode` option. The channel toggles are booleans because there are only two meaningful states each. We initially considered three-state `push_mode` (`always` / `when_away` / `never`) but `always` is a fake state — pushing while the user is actively reading the room is bad UX, no app does it, and the underlying decision tree only has two states regardless of UI labels.

**Snooze representation**: two columns — `snooze_indefinite` (boolean, `null: false, default: false`) and `snooze_until` (datetime, nullable). Mutually exclusive: `snooze!("indefinite")` sets `snooze_indefinite: true` and clears `snooze_until`; the other presets clear `snooze_indefinite` and set `snooze_until` to a real future timestamp. `snoozed?` reads both. Two columns is cheap; the magic-timestamp `Time.utc(2099, 1, 1)` sentinel approach was rejected because it creates ambiguity for any code reading `snooze_until` outside `snoozed?`/`indefinite?` (analytics, debugging, admin tooling, future date-picker UI). Intent in the schema, not in a constant. `Time.zone.now` (Rails-set application timezone) drives `until_tomorrow` resolution; per-user timezone is out of scope (no `users.time_zone` column today; revisit when we add user TZ).

`User` association + delegates:

```ruby
class User < ApplicationRecord
  has_one :notification_settings, class_name: "User::NotificationSettings", dependent: :destroy
  after_create_commit :create_default_notification_settings!,
    unless: -> { notification_settings.present? }

  delegate :snoozed?, :snooze!, :unsnooze!, :mode, :email_when_away?, :push_enabled?,
           :default_involvement_for_new_membership, to: :notification_settings

  private
    def create_default_notification_settings!
      # has_one's generated build_*/create_* helper. Persists with column defaults
      # (mode: "mentions_and_dms", email_when_away: false, push_enabled: true).
      create_notification_settings!
    end
end
```

The bulk-apply lives on `User::NotificationSettings#apply_to_all_rooms!` (see definition above) — the settings record owns the `mode` source-of-truth, so the bulk update reads naturally as `user.notification_settings.apply_to_all_rooms!`. The earlier `User#apply_notification_mode_to_all_rooms!` was rejected on DHH-style review because the verb belongs on the record that owns the value being applied, and the long procedural name read like a service method.

Unsubscribe tokens are NOT generated via `generates_token_for` — that primitive can't carry tenant identity, which SaaS requires (see Email pipeline § Unsubscribe). Tokens are minted via `Rails.application.message_verifier(:email_unsubscribe)` with a `{ user_id, tenant }` payload and a 1-month expiry (CAN-SPAM compliant, avoids dead-link permanence — pattern adapted from Fizzy's `User::Notifiable`).

### Migrations

Three migrations in v1:

```ruby
create_table :user_notification_settings do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.string   :mode,              null: false, default: "mentions_and_dms"
  t.boolean  :email_when_away,   null: false, default: false
  t.boolean  :push_enabled,      null: false, default: true
  t.boolean  :snooze_indefinite, null: false, default: false  # mutually exclusive with snooze_until
  t.datetime :snooze_until                                    # null when snooze_indefinite or not snoozed
  t.timestamps
end

add_column :memberships, :last_email_notified_at, :datetime
add_column :accounts,    :email_notifications_enabled, :boolean, default: false, null: false
```

- `user_notification_settings` — one row per user, built on user creation. Real columns get real Rails affordances: `enum :mode` with bang methods, dirty tracking, AR callbacks, `saved_change_to_*?`, query scopes. **Backfill on deploy** (idempotent — safe to re-run after a partial failure or in seeded test environments): `User.where.missing(:notification_settings).find_each(&:create_notification_settings!)`. The `where.missing` filter is essential — `User.find_each(&:create_notification_settings!)` would raise `RecordNotUnique` against the unique `user_id` index if any rows already exist. Defaults — `mode: "mentions_and_dms"`, `email_when_away: false`, `push_enabled: true` — reproduce today's gates exactly, so deploy is zero-behavior-change.
- `memberships.last_email_notified_at` — per-user-per-room cooldown anchor. 5-minute cooldown enforced atomically via `Membership#claim_email_cooldown!` (`Membership::EMAIL_COOLDOWN = 5.minutes`) — a single conditional `UPDATE ... WHERE last_email_notified_at IS NULL OR last_email_notified_at <= ?` that both checks freshness and stamps the timestamp, returning true only if this caller won the slot. Race-safe under concurrent jobs (5 simultaneous mention dispatches → exactly 1 email). Cooldown logic lives on the model where the column lives, not on the job. Composite `(user_id, room_id)` index already exists; no new index needed.
- `accounts.email_notifications_enabled` — per-account feature flag, default off. Read via `Sabha.email_notifications?` (top-level predicate added to `lib/sabha.rb`, parallel to the existing `Sabha.saas?`): `ENV["SABHA_EMAIL_NOTIFICATIONS"] == "1" || Account.sole.email_notifications_enabled?`. Lets us ship dark and turn email on per workspace before flipping the env default.

`destroy_all_associated_records` on `User` must be updated to include `notification_settings` (per `CLAUDE.md`'s reminder about associations and active-scoped `dependent: :destroy`).

## Multi-tenant scope (SaaS)

All notification configuration is **per-workspace**, by construction. No extra design work is needed to get this — every preference lives on a tenanted record:

| Lives on | Storage | Effect |
|---|---|---|
| Global `mode`, `email_when_away`, `push_enabled`, `snooze_until` | `user_notification_settings` (tenanted DB) | Set independently in each workspace. Snooze in workspace A does not silence B. |
| Per-room `Membership#involvement` | `memberships` (tenanted DB) | Already per-workspace. |
| `last_email_notified_at` cooldown | `memberships` (tenanted DB) | Cooldown windows are per-workspace, per-room. |
| `Push::Subscription` | tenanted DB | Devices registered in workspace A only push for A's events. |

A user in three workspaces gets three independent `User` rows (one per tenant via `activerecord-tenanted`), each with its own `user_notification_settings` row. The only shared element is the `GlobalIdentity` (login + email address), which is the right boundary — outbound mail uses that one address no matter which workspace fired it, but the *decision* to send and the *content* of the email come entirely from the tenanted side.

**Cross-workspace concerns:**

- **Unsubscribe links** — the `Rails.application.message_verifier(:email_unsubscribe)` payload binds `{ user_id, tenant }` together. The controller decodes the token, enters the encoded tenant via `ApplicationRecord.with_tenant(...)`, then flips `email_when_away: false`. A click on an unsubscribe link from workspace A flips A's setting only; the same user-id in workspace B is untouched. Self-hosted: `tenant: nil`, `with_tenant` is a no-op.
- **Email subject prefix** — `"[#{Account.sole.name}] "` runs inside the resolved tenant, so multi-workspace users can tell which inbox a mention came from at a glance.
- **Cross-workspace shared snooze** — explicitly out of scope (see Out of scope §). Would require an untenanted column on `WorkspaceMembership` and a cross-tenant lookup at dispatch time. Defer until users ask.

In single-tenant (self-hosted) mode this section is a no-op: there's one workspace, so "per-workspace" collapses to "global per user".

## Email pipeline

**Mailers** (added to `app/mailers/user_mailer.rb`):

- `mention_notification(user, message)` — subject `"#{actor.name} mentioned you in #{room.display_name}"`, prefixed with `"[#{Account.sole.name}] "` in SaaS so multi-workspace users can tell which inbox the mention came from.
- `direct_message_notification(user, message)` — subject `"#{actor.name} sent you a message"`.

Both mailers attach RFC 8058 unsubscribe headers via an inline `after_action` on `UserMailer` — **no concern, single caller in v1**. Fizzy ports the same logic into `Mailers::Unsubscribable`, but Fizzy already has a second caller (`Notification::BundleMailer`); Sabha v1 has only `UserMailer`. Extract to a concern when v1.1's `BundleMailer` lands, not before:

```ruby
class UserMailer < ApplicationMailer
  after_action :set_unsubscribe_headers, only: %i[ mention_notification direct_message_notification ]

  # ... mailer methods that mint @unsubscribe_token before calling mail() ...

  private
    def set_unsubscribe_headers
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
      headers["List-Unsubscribe"]      = "<#{email_unsubscribes_url(token: @unsubscribe_token, script_name: '')}>"
    end
end
```

Each mailer method mints `@unsubscribe_token` via `Rails.application.message_verifier(:email_unsubscribe).generate({ user_id: user.id, tenant: ApplicationRecord.current_tenant, target_state: false }, expires_in: 1.month, purpose: :email_unsubscribe)` (full shape in the Unsubscribe subsection below). The `target_state: false` field is the single-use guard — at verify time the controller rejects the token if `email_when_away` is already `false`, so a token that has achieved its purpose can't be replayed (e.g., to re-disable email after an admin or user re-enables it). **Do not use `User#generate_token_for(:email_unsubscribe)` — that primitive can't carry tenant identity, which SaaS requires.** Centralize the token mint in a private mailer helper (`def unsubscribe_token_for(user); ...; end` on `UserMailer`, promoted to `ApplicationMailer` when v1.1's `BundleMailer` arrives).

Templates render `message.plain_text_body.truncate(280)`, a CTA link to `room_at_message_url(room, message)`, "Manage notifications" link to the settings panel, and an in-body unsubscribe link (the human path; the header is the MUA path).

**Job** (`app/jobs/notification/email_job.rb`) — scheduled with `wait: Notification::EmailJob::EMAIL_GRACE_WINDOW` (5 minutes). Declares `discard_on ActiveJob::DeserializationError` (mirroring `app/jobs/room/push_message_job.rb`) so a message or membership deleted during the grace window cleanly drops the job rather than retrying. Same pattern on `Notification::DispatchJob`. At fire time the job is a **shallow wrapper** that delegates to a per-activity-type `User` method — substance lives on the model where the data lives, per the DHH "jobs are shallow wrappers calling model methods" pattern (`architecture.md` § background_jobs). The model methods **re-run the same `Membership::Notifiable` predicate** the dispatch path uses, so state changes during the grace window (block toggled, message deleted, room destroyed, account flag flipped, membership revoked) all flow through the same gate that approved the dispatch — no duplicate logic.

The job dispatches to a named `User#email_<activity_type>_notification` method via `public_send`. Splitting per activity_type — instead of one `send_notification_email(message, activity_type)` with a `case` switch — keeps each public verb on `User` self-evident and eliminates the procedural switch:

```ruby
# app/jobs/notification/email_job.rb
class Notification::EmailJob < ApplicationJob
  EMAIL_GRACE_WINDOW = 5.minutes

  discard_on ActiveJob::DeserializationError

  def perform(user, message, activity_type)
    return if DemoMode.enabled?
    user.public_send("email_#{activity_type}_notification", message)
  end
end

# app/models/user.rb (added)
def email_mention_notification(message)
  email_notification(message, :mention) { UserMailer.mention_notification(self, message) }
end

def email_direct_message_notification(message)
  email_notification(message, :direct_message) { UserMailer.direct_message_notification(self, message) }
end

private
  def email_notification(message, activity_type)
    membership = memberships.find_by(room_id: message.room_id)
    return unless membership&.receives_email_for?(message, activity_type)
    return unless membership.claim_email_cooldown!

    yield.deliver_now
  rescue Net::SMTPFatalError, Net::SMTPSyntaxError => e
    # Permanent SMTP failure (5xx) — address is undeliverable. Auto-suppress
    # to protect sender-domain reputation for transactional mail (verification,
    # password reset). v1.1 replaces this with provider-webhook-driven
    # suppression; this is the minimum guard for the v1 → v1.1 gap window.
    notification_settings.update!(email_when_away: false)
    Rails.logger.warn("[notification] permanent SMTP failure for user=#{id}: #{e.message}; auto-suppressed")
  end

# app/models/membership.rb (added)
EMAIL_COOLDOWN = 5.minutes

# Atomic claim: a single conditional UPDATE that both checks freshness and
# stamps the timestamp. Returns true if this caller won the slot, false if
# another concurrent dispatch claimed it first. Race-safe under SQLite's
# write serialization and Postgres row-level locks — eliminates the
# read-then-write window that would let "5 fast mentions" send 5 emails.
def claim_email_cooldown!
  rows = self.class.where(id: id).where(
    "last_email_notified_at IS NULL OR last_email_notified_at <= ?", EMAIL_COOLDOWN.ago
  ).update_all(last_email_notified_at: Time.current)
  rows > 0
end
```

`return unless user && message` is dropped — `discard_on ActiveJob::DeserializationError` already handles the missing-record case, matching `Room::PushMessageJob` exactly. The `EMAIL_GRACE_WINDOW` constant stays on the job (it controls `wait:`, a job-runtime concern); `EMAIL_COOLDOWN` lives on `Membership` because the cooldown is a business policy on the room-level relationship, not job runtime. Cooldown is **atomic** on `Membership` — `claim_email_cooldown!` does the check-and-stamp in one SQL roundtrip; a separate `recently_emailed?` predicate is intentionally not exposed because using it as a gate would reintroduce the read-then-write race.

`Notification::DispatchJob` follows the same shape and gives `Message#notify_recipients` the standard `_later`/`_now` symmetry from `architecture.md`. The dispatch logic lives on `Message` (orchestration) and `Membership::Notifiable` (predicates) — see the per-recipient decision tree section above for the full shape:

```ruby
# app/models/message.rb (added)
def notify_recipients_later(activity_type, actor: nil)
  Notification::DispatchJob.perform_later(self, activity_type, actor)
end

# app/jobs/notification/dispatch_job.rb
class Notification::DispatchJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(message, activity_type, actor = nil)
    return if DemoMode.enabled?
    message.notify_recipients(activity_type, actor: actor)
  end
end

# Boost callback (replaces Boost#create_boost_notification):
# return if message.room.direct? || message.room.parent_room&.direct?
# message.notify_recipients_later(:boost, actor: booster)
#
# Membership#deliver_notification resolves actor: actor || message.creator.
# Default callers (mention/everyone/DM/thread) pass nothing → message.creator.
```

**A message can fire multiple activity_types.** A regular message in an open/closed room is always an `:everyone_room_message` (delivers to users on `involvement: :everything`); if it also has mentions, it is *additionally* a `:mention` (delivers to mentionees on `involvement: :mentions`). The two activity_types target disjoint membership scopes (see "Disjointness invariant" above), so each is its own dispatch.

`Room#notify_later(message)` (the rename from `#push_later`) computes `applicable_activity_types(message)` and enqueues **one `Notification::DispatchJob` per type**. The job signature stays simple: `perform(message, activity_type)`. Concretely:

```ruby
# app/models/room.rb
def notify_later(message)
  applicable_activity_types(message).each do |activity_type|
    message.notify_recipients_later(activity_type)
  end
end

# Default — open/closed rooms
def applicable_activity_types(message)
  types = [ :everyone_room_message ]
  types << :mention if message.mentions_everyone? || message.mentionees.any?
  types
end

# app/models/rooms/direct.rb — overrides
def applicable_activity_types(_message)
  [ :direct_message ]
end

# app/models/rooms/thread.rb — overrides
def applicable_activity_types(_message)
  [ :thread_reply ]
end
```

`:boost` does not flow through `Room#notify_later` — it's triggered by a boost-creation event, dispatched separately. Today's `Boost#create_boost_notification` (`app/models/boost.rb:28`) skips DM rooms and thread-of-DM rooms with `return if message.room.direct? || message.room.parent_room&.direct?`. **The replacement boost callback must retain that guard verbatim before calling `message.notify_recipients_later(:boost)`** — boost notifications in DM/thread-of-DM rooms would be a behavior regression vs today. Keeping the guard at the enqueue site (rather than pushing it into the dispatcher's recipient query) matches today's shape and keeps the dispatcher recipient-set table room-type-agnostic.

Public surface is `message.notify_recipients_later(activity_type)` — same shape as Campfire's `notify_watchers_later`. The N-jobs-per-message design keeps the dispatcher's per-call work narrow (one decision tree pass per (recipient, activity_type)) and lets us schedule per-channel work independently.

Test surface moves with the logic: `User#email_mention_notification` / `#email_direct_message_notification`, `Membership::Notifiable` predicates (`receives_email_for?`, etc.), `Membership#claim_email_cooldown!` (with an explicit concurrent-jobs test that asserts exactly one of N parallel claims wins), `Message#notify_recipients` (the orchestration), and `Membership#deliver_notification` (the per-recipient fan-out) all get tested where they live. Job tests collapse to "do I delegate?" — minimal coverage, since substance is tested on the models.

**Email-at-event-time semantics**: `EmailJob` is scheduled **only if the user is already globally away when the event fires** (`user_globally_away?` returns true at dispatch). A user actively reading the chat at the moment of mention sees the message live and gets no email queued — they didn't miss it. The grace window is purely a *cancellation* mechanism for the case "user was away at event time but came back during the 5 minutes before delivery", not a *capture-on-departure* mechanism for "user was online but might drift offline soon". Without the at-dispatch check, a live reader who closes their laptop 4 minutes after seeing a mention would still get an email about it — wrong product behavior, and inconsistent with Slack / Google Chat / every other chat app.

If the user was online at event time and goes offline ten minutes later, they get nothing for that earlier mention. They'll see it in-app on return (Activity tab + unread badge). This is the deliberate tradeoff: in-app is the truth-on-return surface; email is for "I wasn't there when it happened".

**Job arguments are records (plus the activity_type symbol), not raw IDs.** `EmailJob.perform_later(user, message, activity_type)` and `DispatchJob.perform_later(message, activity_type)` pass tenanted records directly. Per `activerecord-tenanted`, ActiveJob captures the current tenant at enqueue and restores it at perform; tenanted GlobalIDs additionally bind tenant into the serialized argument. Belt-and-suspenders. Raw IDs would bypass the GlobalID layer and rely solely on the tenant-set-at-enqueue belt — silent corruption risk if anyone calls `EmailJob.perform_now(123, 456, :mention)` outside a tenant context. With record arguments, the GlobalID locator refuses to load cross-tenant.

### Mailer URL helpers (SaaS path-based tenancy)

The activerecord-tenanted gem documents subdomain interpolation (`%{tenant}` in `default_url_options[:host]`) but explicitly defers path-based and explicit-host helpers — see `docs/multi-tenant/activerecord-tenanted-guide.md` lines 720–724. Sabha SaaS uses **path-based** tenanting (workspace prefix in the URL). The mention/DM email's CTA link to `room_at_message_url(room, message)` must include the workspace path prefix or it 404s in SaaS.

**Mechanism (pinned in this plan, not deferred)**: a tenant-aware `script_name` helper on `ApplicationMailer`, called explicitly per URL helper invocation. Pattern matches existing `WorkspaceMailer#welcome` (`saas/app/mailers/workspace_mailer.rb:20-21`) which already uses `script_name: workspace.slug`; only addition is the tenant-to-workspace lookup since mention/DM mailers run inside a tenanted job context (the workspace is implicit via `ApplicationRecord.current_tenant`, not passed as an argument):

```ruby
# app/mailers/application_mailer.rb
def workspace_script_name
  return "" unless Sabha.saas?
  Workspace.find_by(external_id: ApplicationRecord.current_tenant)&.slug || ""
end

# app/mailers/user_mailer.rb (mention/DM templates use it explicitly)
@cta_url = room_at_message_url(room, message, script_name: workspace_script_name)
```

`Workspace#slug` returns `"/#{external_id}"` (`saas/app/models/workspace.rb:30-32`), so the resulting CTA URL is `https://app_host/{workspace_external_id}/rooms/{room_id}/at/{message_id}` — what the SaaS path rewriter (`saas/lib/sabha/saas/path_rewriter.rb`) expects. In self-hosted mode (`Sabha.saas?` is false) the helper returns `""` and URLs render at the top level — no behavior change vs today.

**The unsubscribe URL is workspace-prefix-free, on purpose** — it lives at top-level (no tenant in path), and the signed token's `{ user_id, tenant }` payload carries tenancy. Pass `script_name: ""` explicitly when generating it to harden against future ActionMailer URL-config drift:

```ruby
@unsubscribe_url = email_unsubscribes_url(token: @unsubscribe_token, script_name: "")
```

**Unsubscribe** (`app/controllers/email_unsubscribes_controller.rb`) — two coexisting paths:

- **In-body link, two-step flow** (humans clicking the visible "Unsubscribe" link):
  - `GET /email_unsubscribes/:token` — confirmation page with a single button.
  - `POST /email_unsubscribes` — flips `email_when_away` to `false`, shows "we won't email you" + a toggle to re-enable.
  - Two-step defends against email-client GET prefetchers that auto-fetch links.
- **RFC 8058 one-click header** (Gmail / Apple Mail / Yahoo native unsubscribe button):
  - `POST /email_unsubscribes?token=…` — same flip, no confirmation page. Idempotent.
  - Mailers set `List-Unsubscribe: <https://…/email_unsubscribes?token=…>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers.
  - Required for Gmail and Yahoo bulk-sender compliance (Feb 2024 deliverability rules) — without these headers, transactional mail is more likely to land in spam.

**Auth + CSRF exemptions** (required — controllers default to `before_action :require_authentication` and `protect_from_forgery with: :exception` via `app/controllers/concerns/authentication.rb:5`). The class skeleton:

```ruby
class EmailUnsubscribesController < ApplicationController
  layout "mailer"                                    # account-free layout — top-level route bypasses tenant resolution; default app layout calls Account.sole and would NPE here
  allow_unauthenticated_access                       # the token IS the auth
  skip_forgery_protection only: %i[create]           # cross-origin POST from MUAs is the whole point
  rate_limit to: 30, within: 5.minutes, only: %i[create]

  # GET /email_unsubscribes/:token — confirmation page
  def show; end

  # POST /email_unsubscribes  (form submit OR RFC 8058 one-click)
  def create
    payload = Rails.application.message_verifier(:email_unsubscribe).verified(
      params[:token], purpose: :email_unsubscribe
    )
    return head :not_found unless payload

    ApplicationRecord.with_tenant(payload[:tenant]) do
      settings = User.find(payload[:user_id]).notification_settings
      # Single-use guard: a token whose target_state matches the current state
      # has already been consumed — reject to prevent replay. Without this,
      # an attacker who captured a sent token could re-disable email after a
      # legitimate re-enable.
      return head :gone if settings.email_when_away == payload[:target_state]
      settings.update!(email_when_away: payload[:target_state])
    end
    head :ok
  end
end
```

The `allow_unauthenticated_access` class method already exists on `Authentication` (no need to invent it). `skip_forgery_protection` is scoped to `create` only — the GET confirmation page is safe under default protection. Rate limit (Rails 8 `rate_limit`) prevents token-spray abuse even though the signed payload itself is the gatekeeper.

**Layout note**: `layout "mailer"` is required because the unsubscribe routes are deliberately registered top-level (no tenant prefix), so the SaaS path rewriter (`saas/lib/sabha/saas/path_rewriter.rb`) doesn't resolve a tenant before the controller runs. Without an alternate layout, the default `application.html.erb` calls `fresh_account_logo_path` → `Current.account` → `Account.sole`, which raises `ActiveRecord::Tenanted::CurrentTenantUnsetError` in SaaS. The mailer layout is account-free and renders cleanly without tenant context.

**Token shape — tenant-bound `MessageVerifier`, not `generates_token_for`.** `generates_token_for` can't carry a workspace identifier in the payload, and SaaS requires the controller to enter the right tenant *before* loading the user (`User` is tenanted, so cross-tenant lookups can't happen safely). The plan uses `Rails.application.message_verifier` directly:

```ruby
# Generation (in mailer, while inside the tenant)
@unsubscribe_token = Rails.application.message_verifier(:email_unsubscribe).generate(
  { user_id: user.id, tenant: ApplicationRecord.current_tenant, target_state: false },
  expires_in: 1.month, purpose: :email_unsubscribe
)

# Validation (in controller, no tenant yet)
payload = Rails.application.message_verifier(:email_unsubscribe).verified(
  params[:token], purpose: :email_unsubscribe
)
return head :not_found unless payload
ApplicationRecord.with_tenant(payload[:tenant]) do
  user = User.find(payload[:user_id])
  # Reject replays: token already achieved its purpose if current state matches target.
  return head :gone if user.notification_settings.email_when_away == payload[:target_state]
  user.notification_settings.update(email_when_away: payload[:target_state])
  # render confirmation
end
```

The signed payload binds user-id and tenant together — a token from workspace A can't be reused against workspace B's user with the same id, and an attacker can't substitute the tenant outside the signature. 1-month expiry satisfies CAN-SPAM and avoids dead-link permanence. Self-hosted mode passes `tenant: nil` and the `with_tenant` block degrades to a no-op (`activerecord-tenanted` handles this).

**Feature flag**: `Sabha.email_notifications?` — true when `ENV["SABHA_EMAIL_NOTIFICATIONS"] == "1"` OR `Account.sole.email_notifications_enabled?` (column added in this v1's migrations — see Data model § Migrations). Defined on the existing top-level `Sabha` module (`lib/sabha.rb`), parallel to the existing `Sabha.saas?` predicate — same shape, same precedent. Lets us ship dark and turn on per-account/tenant before flipping the env default.

## Snooze UX

Two columns on `user_notification_settings` represent snooze state: `snooze_indefinite` (boolean, `null: false, default: false`) and `snooze_until` (datetime, nullable). They're mutually exclusive — `snooze!("indefinite")` sets the boolean and clears the timestamp; the time-bound presets (`1h`/`4h`/`until_tomorrow`) clear the boolean and set the timestamp to a real future moment. `snoozed?` reads both: `snooze_indefinite? || (snooze_until.present? && snooze_until > Time.current)`. Two columns with explicit semantics over a magic-timestamp sentinel — see Data model § `User::NotificationSettings`.

Quick toggle in the sidebar bell icon (`app/views/users/sidebars/_bell.html.erb`) opens a popover with presets. Stimulus controller `app/javascript/controllers/snooze_controller.js` posts to `users/me/notifications/snooze` (singular resource — see Settings UI § routes).

Full controls live in the new Notifications section of the profile.

**Interaction states** (shared between the bell popover and the profile section's Snooze block — define once, render in both surfaces):

| State | Content |
|---|---|
| Idle (not snoozed) | Heading "Pause notifications". Preset buttons: "For 1 hour", "For 4 hours", "Until tomorrow morning", "Indefinitely". The "Until tomorrow morning" label is intentionally relative — the resolved time (8 AM in `Time.zone`) is shown in the next state. |
| Snoozed | Heading "Snoozed until {time} ({tz_abbrev})" + secondary "Turn off snooze" button. Time format: `"5 PM"` for same-day, `"8 AM tomorrow"` for next-day, `"Indefinitely"` for the sentinel. The `{tz_abbrev}` qualifier (e.g. `PST`, `UTC`) renders the application timezone explicitly so users in other zones aren't surprised when notifications resume. Drawn from `Time.zone.now.zone` — see note on per-user TZ below. |
| Loading | The triggered preset button enters disabled state with an inline spinner replacing its label (Sabha's standard `data-loading` pattern). Other presets disabled until response. |
| Error | Inline copy below the presets: "Couldn't update snooze — try again." Buttons remain enabled for retry. No flash banner — popover-local feedback only. |

The profile section's Snooze block renders the same four states with the same copy. Snoozing from one surface updates the other on the next page load (no cross-surface live sync in v1 — they're rarely open simultaneously).

**Mobile vs desktop placement.** Sabha's sidebar is overlay on mobile, docked on desktop (per `CLAUDE.md`). The bell icon lives at the top of the sidebar on both. On desktop, the popover anchors to the bell as a small dropdown (~280px wide). On narrow viewports (mobile overlay sidebar, < 640px), the popover renders as a **bottom sheet** instead — full-width within the overlay, slides up from the bottom edge, dismissable by tap-outside or a top-right close button. This avoids cramming a popover into the narrow overlay where it would clip or overflow the sidebar bounds. Tap target on the bell icon meets the 44×44px minimum implied by `CLAUDE.md`'s WCAG AA baseline.

`"until_tomorrow"` resolves to **next 8 AM in `Time.zone`** (the application's configured `Rails.application.config.time_zone`). There is no `users.time_zone` or `accounts.time_zone` column today (verified against `db/schema.rb`); per-user TZ resolution is out of scope and revisited if a user-TZ column lands.

What snooze suppresses: **push + email**. **In-app rows still get created** so the Activity tab shows what was missed on return.

## Settings UI

New partial `app/views/users/profiles/_notifications.html.erb`, rendered above the existing memberships fieldset in `app/views/users/profiles/show.html.erb`. The per-room involvement loop moves under a `<h3>Per-room overrides</h3>` subhead inside the new fieldset.

Sections, top to bottom:

1. **Mode** — radio group with per-option helper text:

   - **All messages** — "Every message in every room you join, by default."
   - **Mentions and DMs** (default) — "Only when someone @mentions you, posts in `@everyone`, or DMs you."
   - **Nothing** — "Stay in rooms but don't push or email. Your Activity tab still shows mentions on return."

   Group helper text above the radios: "This is the default for rooms you join. Each room can be overridden below." Below the radios, a checkbox: **"Also apply to all my existing rooms"** — **always unchecked by default**, regardless of which mode is picked. The user must opt in to the bulk reset deliberately because it's a destructive operation that overwrites per-room overrides. The label shows a count when the user changes the mode dropdown via Stimulus: "This will overwrite involvement on N rooms (X currently set to all messages, Y to mentions only)." On submit, if checked, `current_user.notification_settings.apply_to_all_rooms!` walks `user.memberships.visible.without_direct_rooms` and updates each `involvement` to the mapping in the layering table.

   The "Nothing" mode helper text deliberately distinguishes it from per-room `:nothing` (which silences in-app too). In v1, unread badge counter behavior remains unchanged; v1.2 will decide whether per-room `:nothing` should also suppress badge bumps.

   **Response shape**: `Users::Notifications::PreferencesController#update` responds with a `turbo_stream` that (a) updates the form's inline "Saved" indicator next to the submit button (Sabha's standard `data-controller="form-status"` pattern), and (b) when the bulk-apply checkbox was checked, prepends a flash notice: `"Updated {N} rooms to match your default."` (where `N` is the row count returned from `notification_settings.apply_to_all_rooms!`). Wrap the `apply_to_all_rooms!` call and the settings save in a single `ActiveRecord::Base.transaction` so a failure rolls both back. On `ActiveRecord::StatementInvalid`, re-render the form with a generic error notice (`"Couldn't save — try again."`) and leave per-room values untouched.

   The Email and Push toggles in the same form post separately to `notifications/email` (create/destroy) and `notifications/push` (create/destroy) via Turbo — small per-toggle endpoints, each ~5 lines of controller code calling the corresponding `User::NotificationSettings` verb (e.g. `email_when_away_on!`).
2. **Snooze** — current state ("Snoozed until 5pm" or "Off"), preset buttons, "Turn off snooze" when active.
3. **Email** — single toggle: "Email me about mentions and DMs when I'm away". When the feature flag is off for this account, the toggle is **visible but disabled** (not hidden — visibility communicates the feature exists), with helper text below: "Email notifications aren't enabled for this community yet." Sabha's warm tone — no "your administrator has disabled this" framing — preserves restraint and avoids sounding like a permissions-gate error.
4. **Push** — single toggle: "Push notifications". Plus the existing device list (move `app/views/users/push_subscriptions/index.html.erb` content inline). No three-state — push fires when the membership is disconnected from the room, period; the toggle is on/off.
5. **Per-room overrides** — existing `_membership.html.erb` loop, unchanged. Helper text: "Overrides your default for individual rooms."

New routes (in `config/routes.rb`, scoped under `users/me`) — split into per-toggle noun resources under a `:notifications` namespace, matching the 37signals "verbs become nouns" pattern. Each boolean preference becomes a singular resource with `create`/`destroy` (turning the feature on is creating a subscription; off is destroying it); the multi-value `mode` enum stays as `update` since it picks from a fixed set:

```ruby
namespace :notifications do
  resource :preference, only: %i[update]      # mode (3-value enum: nothing / mentions_and_dms / all)
  resource :snooze,     only: %i[create destroy]
  resource :email,      only: %i[create destroy]   # email_when_away on/off
  resource :push,       only: %i[create destroy]   # push_enabled on/off
end
```

Resulting paths: `PATCH /users/me/notifications/preference`, `POST /users/me/notifications/snooze`, `DELETE /users/me/notifications/email`, etc. The Settings UI form posts to multiple endpoints — the Mode block hits `notifications/preference`, the Email/Push toggles hit their respective `notifications/email` / `notifications/push` resources via Turbo. The bell-icon quick toggle hits `notifications/snooze`. Each controller is small (one or two actions, ~5 lines per action), and each delegates to a model verb on `User::NotificationSettings`: `mode!`, `snooze!`, `unsnooze!`, `email_when_away_on!`/`off!`, `push_enabled_on!`/`off!`.

(Earlier draft used a single `resource :notification_settings, only: %i[update]` with a multi-field form. Rejected on DHH-style review because it's procedural — one update endpoint accepting a soup of fields is the shape DHH replaces with noun resources, where each toggle becomes its own create/destroy. Browsers, Turbo, and the audit trail all benefit: each preference change is its own verb on its own URL.)

Plus top-level: `resources :email_unsubscribes, only: %i[show create], param: :token`. **Registered outside any tenant routing constraint** (peer of `/session/new`, `/workspaces`) so the controller can decode the signed token before the middleware needs to resolve a tenant from the URL. The token's `{ user_id, tenant }` payload is the sole source of tenancy for this route. The controller is `EmailUnsubscribesController` (no `Users::` namespace) since it is not user-scoped — it's accessed unauthenticated by token from outside the app.

## Files

### Namespace

Gating predicates live as a concern on `Membership` (`Membership::Notifiable`), matching the broader `Membership::Connectable` precedent. Routing/orchestration lives on `Message` (`#notify_recipients`, `#notify_recipients_later`). Transport classes hang off the existing `Notification` model — `Notification::Channel::Push`, `Notification::Channel::Push::{Base,Web}`, `Notification::DispatchJob`, `Notification::EmailJob`. Direct parity with Fizzy's `Notification::Pushable`/`PushTarget::Web` shape. Earlier drafts used `Notifications::` (plural) as an invented top-level namespace and a `Notification::Dispatcher` service-object class — both dropped. `CLAUDE.md` mandates namespace decomposition off existing models (`User::Role`, `Message::Searchable`, `Room::MessagePusher`); putting routing on `Message` and gates on `Membership` honors that, and singular `Notification::` for transports matches Fizzy verbatim. Rejected `Message::Notifier` (suggested by review) because the transport code (`Channel::Push`, `EmailJob`) isn't naturally about a Message — it's about delivery of a notification-worthy event.

### New

- `app/models/user/notification_settings.rb` — real AR record on the new `user_notification_settings` table. Direct Fizzy parity with `User::Settings`. `enum :mode`, three boolean/datetime columns, `belongs_to :user`. AR callbacks (`saved_change_to_*?`) replace hand-rolled mutators.
- `app/models/concerns/membership/notifiable.rb` — concern on `Membership` that owns all per-recipient gating predicates: `receives_in_app_row_for?`, `receives_push_for?`, `receives_email_for?`, plus shared `notifiable_for?` / `deliverable_outbound?` privates. Constants `IN_APP_ROW_TYPES`, `EMAIL_TYPES`. **No Event class hierarchy and no Dispatcher class** — `activity_type` is a symbol that matches the existing `notifications.activity_type` column; predicates are constant lookups combined with per-recipient state. Matches Fizzy's `Notification::Pushable` concern shape, on the right model: gating on `Membership` (which owns the user/room/involvement triple), transports under `Notification::`. (Earlier draft proposed a `Notification::Dispatcher` service-object class with a `Decision = Data.define(...)` value tuple — dropped on DHH-style review because the predicates belong on the record that owns the state, not on a static-method service.)
- `app/models/notification/channel/push.rb` — facade that fans out to registered push targets. **Direct parity with Fizzy's shipped `Notification::Pushable` concern** (`fizzy/app/models/notification/pushable.rb`), ported to Sabha's namespace. The signature takes `(message, membership)` rather than a `Notification` record — Sabha's non-row activity_types (`:direct_message`, `:everyone_room_message`) push without persisting a Notification row, so the carrier is the `(message, recipient_membership)` pair:

  ```ruby
  class Notification::Channel::Push
    class_attribute :push_targets, default: []

    class << self
      def register_push_target(target)
        target = resolve_push_target(target)
        push_targets << target unless push_targets.include?(target)
      end

      def deliver(message, membership)
        push_targets.each { |target| target.process(message, membership) }
      end

      private
        def resolve_push_target(target)
          target.is_a?(Symbol) ? "Notification::Channel::Push::#{target.to_s.classify}".constantize : target
        end
    end
  end

  # Boot-time registration (config/initializers/notification.rb):
  Notification::Channel::Push.register_push_target(:web)
  # Future: Notification::Channel::Push.register_push_target(:apns)
  ```

- `app/models/notification/channel/push/base.rb` — base class for push targets, mirroring Fizzy's `Notification::PushTarget` (`fizzy/app/models/notification/push_target.rb`):

  ```ruby
  class Notification::Channel::Push::Base
    attr_reader :message, :membership

    def self.process(message, membership) = new(message, membership).process

    def initialize(message, membership)
      @message = message
      @membership = membership
    end

    def process = raise NotImplementedError
  end
  ```

- `app/models/notification/channel/push/web.rb` — WebPush delivery, mirroring Fizzy's `Notification::PushTarget::Web` (`fizzy/app/models/notification/push_target/web.rb`) which queues to `Rails.configuration.x.web_push_pool`:

  ```ruby
  class Notification::Channel::Push::Web < Notification::Channel::Push::Base
    def process
      Rails.configuration.x.web_push_pool.queue(payload, subscriptions) if subscriptions.any?
    end

    private
      def payload = Room::MessagePusher.build_payload(message, membership)  # today's push copy, unchanged
      def subscriptions = @subscriptions ||= membership.user.push_subscriptions
  end
  ```

  **Native APNs and FCM are roadmap items for Sabha mobile**, and Fizzy's structure is what we'll plug `::Apns` / `::Fcm` siblings into when we ship — same as Fizzy will. Naming the v1 implementation `::Web` is required for that registration to make sense, not future-proofing for its own sake.
- **No `Mailers::Unsubscribable` concern in v1.** `UserMailer` is the single caller, so the 6-line `set_unsubscribe_headers` is inlined as a private method on `UserMailer` directly (see Email pipeline § Mailers above). Per `CLAUDE.md`'s "don't extract small chunks" rule, extract to `app/mailers/concerns/mailers/unsubscribable.rb` when v1.1's deferred `Notification::BundleMailer` (the second caller) lands — at that point the extraction matches Fizzy's shipped shape and earns its keep.
- `app/jobs/notification/dispatch_job.rb` — replaces `Room::PushMessageJob`. Shallow wrapper: `def perform(message, activity_type, actor = nil) = (return if DemoMode.enabled?; message.notify_recipients(activity_type, actor: actor))`. `discard_on ActiveJob::DeserializationError`. The `actor` argument carries the user who triggered the event when it differs from `message.creator` — used by `:boost` (the booster). Defaults to nil; `Membership#deliver_notification` resolves `actor || message.creator` at row-creation time.
- `app/jobs/notification/email_job.rb` — shallow wrapper: `def perform(user, message, activity_type) = (return if DemoMode.enabled?; user.public_send("email_#{activity_type}_notification", message))`. Defines `EMAIL_GRACE_WINDOW = 5.minutes` (job-runtime concern). `discard_on ActiveJob::DeserializationError`. The `public_send` dispatches to `User#email_mention_notification(message)` or `User#email_direct_message_notification(message)` — named verbs on the model rather than a procedural `case` switch on `activity_type`. (Email channel doesn't carry actor since v1's email is mention + DM only — neither uses a different actor.)
- `app/views/user_mailer/{mention_notification,direct_message_notification}.{html,text}.erb`.
- `app/views/users/profiles/_notifications.html.erb`.
- `app/controllers/users/notifications/preferences_controller.rb` — `update` action: assigns `mode` (and triggers `notification_settings.apply_to_all_rooms!` when the bulk-apply checkbox is checked).
- `app/controllers/users/notifications/snoozes_controller.rb` — `create` (with preset param) / `destroy`.
- `app/controllers/users/notifications/emails_controller.rb` — `create` (turn `email_when_away` on) / `destroy` (turn off).
- `app/controllers/users/notifications/pushes_controller.rb` — `create` (turn `push_enabled` on) / `destroy` (turn off).
- `app/controllers/email_unsubscribes_controller.rb`.
- `app/javascript/controllers/snooze_controller.js`.
- `db/migrate/YYYYMMDDHHMMSS_create_user_notification_settings.rb` (+ a follow-up backfill migration that runs `User.where.missing(:notification_settings).find_each(&:create_notification_settings!)` to seed existing users with column defaults — idempotent, safe to re-run).
- `db/migrate/YYYYMMDDHHMMSS_add_last_email_notified_at_to_memberships.rb`.
- `db/migrate/YYYYMMDDHHMMSS_add_email_notifications_enabled_to_accounts.rb`.

### Modify

- `app/mailers/user_mailer.rb` — add `mention_notification`, `direct_message_notification`.
- `app/models/user.rb` — `has_one :notification_settings` association, `after_create_commit` default-build hook (`create_notification_settings!`), snooze/mode delegates to `notification_settings`. **Add per-activity-type email verbs** — `email_mention_notification(message)` and `email_direct_message_notification(message)` — each calling a private `email_notification(message, activity_type) { yield mailer }` helper that re-runs `membership.receives_email_for?`, atomically claims the cooldown via `Membership#claim_email_cooldown!`, delivers the mailer, and rescues permanent SMTP failures to auto-suppress `email_when_away` (logic moved off `Notification::EmailJob` for shallow-job parity). Add `workspace_locally_away?` predicate (queries `Membership.last_connected_at_for([id])` against the active activity tier). Update `destroy_all_associated_records` to include the new `notification_settings` association. (No `apply_notification_mode_to_all_rooms!` here — the bulk-apply lives on `User::NotificationSettings#apply_to_all_rooms!`, where the `mode` source-of-truth lives.)
- `app/models/room.rb` — (1) `#push_later` → `#notify_later`. `#notify_later` enqueues **one `Notification::DispatchJob` per applicable activity_type** (a single message can fire both `:everyone_room_message` and `:mention`; STI subclasses override `#applicable_activity_types` to narrow the set). (2) Add `#applicable_activity_types(message)` returning `[:everyone_room_message]` plus `:mention` when the message has mentions — base behavior for open/closed rooms. (3) `Room#default_involvement(user:)` reads from `user&.notification_settings&.default_involvement_for_new_membership` with `"mentions"` fallback.
- `app/models/rooms/direct.rb` — override `#applicable_activity_types(_message) = [:direct_message]`. `#default_involvement` stays unchanged so DMs always seed as `"everything"`.
- `app/models/rooms/thread.rb` — override `#applicable_activity_types(_message) = [:thread_reply]`.
- `app/models/message.rb` — (1) Remove `create_mention_notifications` body; row creation moves into `Membership#deliver_notification` (called from `Message#notify_recipients`). (2) **Keep `increment_unread_notifications_counters` and its `after_create_commit` callback unchanged in v1** — unread-counter unification is deferred to v1.2 (see Architecture § Unread counter scope). The reactivation path (`restore_unread_notifications_counters_if_reactivated`) also stays unchanged. (3) **Remove `create_thread_reply_notifications` and its `after_create_commit` callback** — `:thread_reply` is now routed through `Message#notify_recipients` via `Rooms::Thread#applicable_activity_types`, sharing the same block/`receives?` gates as the other activity_types. (4) **Add `notify_recipients(activity_type, actor: nil)` and `notify_recipients_later(activity_type, actor: nil)` instance methods** — the public API for dispatching notifications about a message; `Notification::DispatchJob` is a shallow wrapper that calls `message.notify_recipients(activity_type, actor: actor)`. (5) **Add private `candidate_memberships(activity_type)` and `recipient_user_ids_for(activity_type)`** — the case-switched recipient-resolution helpers per the Per-channel recipient resolution table. **Preserve the `[user, :inbox_activity]` stream-key form** in all `broadcast_*_to` calls — bare symbol streams collide across tenants per the activerecord-tenanted gem's GlobalID guarantees (Sabha team note in `docs/multi-tenant/activerecord-tenanted-guide.md` line 664).
- `app/models/membership.rb` — (1) `include Membership::Notifiable` to attach the gating predicates. (2) Add `receives?(activity_type)` per the truth table at Architecture § Per-recipient decision tree — for `:mention` it reuses today's `receives_mentions?` (`involvement.in?(%w[mentions everything])`) verbatim; for `:everyone_room_message` it requires `involvement == "everything"`; for `:direct_message`/`:boost` it returns true; for `:thread_reply` it requires non-`:nothing`/non-`:invisible`. (3) Add `deliver_notification(message, activity_type, actor:)` — per-recipient fan-out: creates the `Notification` row when `receives_in_app_row_for?`, calls `Notification::Channel::Push.deliver(message, self)` when `receives_push_for?`, and enqueues `Notification::EmailJob` (with grace window) when `receives_email_for?`. (4) **Add `EMAIL_COOLDOWN = 5.minutes` constant + `claim_email_cooldown!` atomic-claim method** — single conditional `update_all` that both checks freshness and stamps the timestamp, returning rows-affected. The non-atomic read/write split (`recently_emailed?` predicate + `record_email_delivery!` bang verb) was rejected because concurrent jobs for fast mentions would all pass the read before any write, defeating the cooldown.
- `app/views/users/profiles/show.html.erb` — render new partial; move per-room loop under it.
- `app/views/users/sidebars/_bell.html.erb` — snooze quick toggle.
- `config/routes.rb` — new resources.
- `lib/sabha.rb` — add `Sabha.email_notifications?` predicate (parallel to existing `Sabha.saas?`).

### Reuse (do not reinvent)

- `Membership::Connectable` — presence (`connected?`, `disconnected` scope, `last_connected_at_for`, `ACTIVITY_TIERS`).
- `Rails.configuration.x.web_push_pool` — push delivery pool.
- `User#blocked?` / `User#blocked_by?` — block check.
- `Branding.mailer_from` and existing mailer layouts.
- `Notification` model — `Membership#deliver_notification` creates rows through it, schema unchanged.

### Delete (after the new dispatch path is proven)

- `app/models/room/message_pusher.rb` — folded into `Notification::Channel::Push::Web` (`#process` calls today's `build_payload` shape directly via the class method preserved on `MessagePusher` until the deletion lands; once `Channel::Push::Web` ships, `MessagePusher` deletes).
- `app/jobs/room/push_message_job.rb` — replaced by `Notification::DispatchJob`.
- `app/jobs/create_thread_reply_notifications_job.rb` — replaced by `Message#notify_recipients(:thread_reply)`. Recipient resolution (thread memberships ∪ parent-room `:everything` members − creator − already-mentioned, skip when parent room is a DM) is ported into the `:thread_reply` recipient query on `Message`.

## Rollout

1. Run migrations: `SAAS=true bin/rails db:migrate:primary` in SaaS (auto-runs against every tenant per the activerecord-tenanted gem's database tasks) or `bin/rails db:migrate` for self-hosted. Then ship `Membership::Notifiable` + `Message#notify_recipients` with `Sabha.email_notifications?` returning false everywhere (env unset, all `accounts.email_notifications_enabled` columns default to false). Push and in-app behavior unchanged because the new path reproduces today's `MessagePusher` recipient matrix exactly under the default settings.
2. Run the existing test suite plus the new `Membership::Notifiable` and `Message#notify_recipients` tests to confirm regression-free push behavior.
3. Enable the email path for one test account by setting `Account#email_notifications_enabled = true` inside that workspace's tenant context.
4. Watch sender domain reputation, bounce rates, and cooldown effectiveness in staging.
5. Toggle on per-account in production. Watch sender domain reputation, bounce rates, and cooldown effectiveness in production for at least one bounce-volume cycle.
6. **Hard gate**: do not flip the env default or remove the flag until v1.1 bounce/spam suppression is deployed (see Out of scope § Deferred to v1.1 — Bounce / spam suppression). Without that suppression, hard bounces accumulate against the sending domain and degrade deliverability for transactional mail (verification, password reset). Step 5 can run for opt-in workspaces under monitoring; step 6 waits on v1.1.

Existing-user defaults at deploy: the backfill migration creates one `user_notification_settings` row per existing `User` using the column defaults — `mode: "mentions_and_dms"`, `push_enabled: true`, `email_when_away: false`, `snooze_until: nil`. **Zero behavior change** at deploy — `mode` only seeds defaults for *future* memberships, so existing per-room `Membership#involvement` values (including `:everything`) deliver exactly as they do today. Push respects today's per-membership disconnected check. Email is feature-flagged off.

## Deferred / Open Questions

### From 2026-05-09 review

- **Email reintroduction premise — name what changed since mailkick was removed.** The `mailkick_subscriptions` table and `memberships.notified_until` were dropped in `db/migrate/20260214163011_remove_mailkick_and_email_notifications.rb` (Feb 2026, ~3 months before this plan). The plan reintroduces email but doesn't explain (a) why mailkick was removed, (b) what changed since to invert the decision, (c) whether this implementation differs from the removed one in ways that don't recreate the original removal reasons. Future maintainers will revisit "should we have email at all?" without that record. Either add a 1-2 paragraph rationale to the **Why** section (preferred) or reframe the goal as a SaaS-acquisition bet rather than a user-pull. *(Source: product-lens persona, 2026-05-09 review.)*

- **Self-hosted vs SaaS email maintenance burden — pick a clear stance.** SaaS has one Sabha-co-operated provider/domain; self-hosted operators inherit DKIM/DMARC/RFC 8058/bounce-handling responsibilities. The plan only addresses SaaS deliverability. Three options: (a) email-when-away is SaaS-only in v1, self-hosted ships with the feature flag hard-disabled; (b) self-hosted ships it with an in-product "configure your sending domain" check + docs page; (c) document operator responsibility explicitly and accept that small operators will hit deliverability problems. Not deciding ships the feature and lets each operator discover the issue in production. *(Source: product-lens persona, 2026-05-09 review.)*

- **Global per-user email cap — shape and threshold.** Beyond the 5-minute per-room cooldown, no global cap in v1. 50 simultaneous mentions across rooms = 50 emails — both a sender-reputation risk (ISPs rate-limit burst senders) and a potential harassment vector (an actor controlling many rooms could flood a target's inbox). Possible shapes: a `user_notification_settings.last_email_sent_at` column with a global cooldown, a `Rails.cache` counter with a per-window cap (e.g. 5 per 10 minutes), or per-recipient throttling at the mail provider. Decision needs product + ops input on burst tolerance and threat model. *(Source: security-lens persona, 2026-05-09 review.)*

- **PII in email subjects — names + room name vs generic subject.** Subjects like `"Alice mentioned you in HR-Investigations"` leak sensitive info to mail servers, MDM systems, archives, and email providers. Decide: (a) accept the PII for engagement (current default), and document the threat model so operators know what they're committing to; (b) add an account-level toggle for generic subjects (`"You have a new notification in Sabha"`); (c) add a per-room sensitivity flag that scrubs subjects for flagged rooms. Affects GDPR Art. 25 (data protection by design) for SaaS deployments. *(Source: security-lens persona, 2026-05-09 review.)*

- **Identity drift toward Slack-shape — examine 5-controls vs brand restraint.** v1 ships 5 settings sections (Mode, Snooze, Email, Push, Per-room overrides). HEY/Campfire (Sabha's brand references) ship ~2-3. The plan's stated parity is Slack/Discord (Sabha's anti-references per `CLAUDE.md`). Tests: (1) which sections could v1 ship without and lose <20% of value? (2) what does this signal to a new user comparing Sabha vs Discord on day one? Either commit to "we are deliberately becoming Slack-class for community chat" or trim. *(Source: product-lens persona, 2026-05-09 review.)*

- **Opt-in default + no in-product nudge means feature stays dark for existing users.** Existing users default to `email_when_away: false` with no discovery surface; industry norm is ~5-10% opt-in for buried profile-page prefs. The implicit goal ("users don't miss important mentions while away") is undercut by the rollout. Three options: (a) name "reach existing users" as out of scope and accept the feature primarily serves new sign-ups; (b) add a one-time discovery banner / Activity-tab toast post-deploy; (c) flip the default to true for *new* users only via a `created_at`-aware backfill, leaving pre-deploy users at false. The current shape is the worst of both worlds — paid feature complexity, low actual adoption. *(Source: product-lens persona, 2026-05-09 review.)*

## Out of scope (v1)

- Thread-reply emails.
- Daily/weekly digests.
- Recurring DND schedules ("every weeknight 9pm–8am").
- Per-activity-type granular toggles ("mentions yes, DMs no").
- Keyword highlights / Slack-style custom triggers.
- Per-room email overrides (room-level controls remain push-only via `involvement`).
- Cross-workspace shared snooze in SaaS.
- Push notification grouping/replacement on the WebPush side.

### Deferred to v1.1

- **Bounce / spam suppression.** Without it, hard bounces and spam reports keep getting mailed → sender reputation degrades → all our mail (including verification, password reset) starts landing in spam. Decision deferred until the production mail provider is locked in: prefer provider webhooks (Postmark, SES via SNS, SendGrid event webhook) for real-time suppression; fall back to the `mailkick` gem as a polling adapter (using only `Mailkick.process_opt_outs_method` to flip our `email_when_away` to `false`, **not** its `has_subscriptions` model — that's the table we deliberately removed). Either path flips the same `user_notification_settings.email_when_away` column.
- **Bundled / digest email.** Fizzy's `Notification::Bundle` model (`app/models/notification/bundle.rb`) is the prior art when we add daily/weekly digests: a per-user time-windowed bundle (`starts_at`/`ends_at`), an `after_create :bundle` hook that finds-or-creates a bundle covering the new notification, a recurring Solid Queue job (`config/recurring.yml`: `every 30 minutes`) that calls `Notification::Bundle.deliver_all` to flush due bundles, and `flush` / `cancel_pending_bundles` to handle frequency changes. Sabha's chat use case wants immediate when-away mail in v1 (a 4-hour-late mention is useless), but the bundle shape maps cleanly onto a future weekly-digest mode.

### Deferred to v1.2

- **Unread badge counter unification.** v1 keeps `Message#increment_unread_notifications_counters`, `Membership#unread_notifications_count`, `Membership#count_unread_notifications_from`, deletion/rebalance/reactivation repair, and live `UnreadNotificationsChannel` behavior unchanged. v1.2 can move counters behind `Membership::Notifiable`, but only with explicit coverage for: synchronous-or-intentionally-async timing, one-`update_all` performance for large rooms, badge broadcasts after successful bumps, soft-delete/hard-destroy decrements, reactivation repair, current DM sender edge case, and the product decision for whether block/per-room `:nothing`/global `mode: nothing` suppress badge bumps.

## Risks and confirmed decisions

- **Layering of global mode vs per-room involvement** — confirmed: per-room `Membership#involvement` is the delivery-time gate; global `mode` only seeds defaults for new memberships. A user with any global mode and room `involvement: :everything` keeps getting all-message push and email — per-room `:everything` overrides even global `nothing`. Settings UI offers an opt-in "Apply to all my rooms" checkbox when changing the global mode.
- **`mode: "nothing"` semantics** — confirmed: suppresses push and email **for non-`:everything` memberships only** (per-room `:everything` always wins, matching Slack's per-channel-override-vs-DND model). In-app rows still fire so the Activity tab tells the truth on return. Snooze owns the master-kill-switch role across all involvements. Unread badge suppression is not changed in v1; v1.2 owns that decision.
- **Block suppression** — confirmed: blocks suppress push, email, and in-app for messages from the blocked user. Mention notification rows are NOT created. Implement via `User#blocked?` / `User#blocked_by?` check inside `Membership::Notifiable#notifiable_for?` (the shared SKIP gate). Unread badge counters keep today's behavior in v1 and are handled in the v1.2 counter-unification work.
- **Email default for existing users** — confirmed: `email_when_away: false`. Opt-in via the new settings panel. Avoids surprise emails for users who deliberately got rid of email when `mailkick` was removed.
- **Unsubscribe pattern** — confirmed: two-step (GET confirmation page + POST flip). Defends against email-client GET prefetchers.
- **Banned/deactivated guard** — explicit early return in `EmailJob`.
- **DemoMode** — replicate the existing `Room::PushMessageJob` early return in `Notification::DispatchJob`.
- **Tenant resolution for unsubscribe links in SaaS** — solved via `Rails.application.message_verifier(:email_unsubscribe)` with `{ user_id, tenant }` payload (see Email pipeline § Unsubscribe). `generates_token_for` is intentionally not used here because it can't bind tenant.
- **Global rate limit** — beyond the 5-minute per-room cooldown, no global per-user cap in v1. If 50 simultaneous mentions across rooms generate 50 emails, accept that. Revisit if abused.
- **Cooldown for DMs** — same 5-minute per-room cooldown applies. A DM room is one room.

## Verification

1. **Unit** — `bin/rails test test/models/user/notification_settings_test.rb test/models/membership/notifiable_test.rb test/models/message_test.rb test/jobs/notification/email_job_test.rb test/mailers/user_mailer_test.rb`. The `Membership::Notifiable` test is a parameterized matrix over `mode × involvement × push_enabled × email_when_away × snoozed × connected_membership × workspace_locally_away × activity_type × blocked` — about 30 representative rows asserting the three predicates (`receives_in_app_row_for?`, `receives_push_for?`, `receives_email_for?`) per case. Must explicitly cover: (a) user with `mode: mentions_and_dms` + room `involvement: :everything` → all-message push fires (regression case from initial review); (b) `@everyone` mention still creates in-app rows for all non-creator room members, even when push routing is narrower; (c) global `mode: nothing` + room `involvement: :everything` → push and email still fire (per-room override wins, regression case from finding 1); (d) existing unread-counter tests still pass unchanged, proving v1 did not move badge semantics.
2. **Integration**:
   - `test/integration/notification/mention_email_flow_test.rb` — mention → DispatchJob → grace window → EmailJob → mail delivered when offline; no mail when connected anywhere.
   - `test/integration/notification/snooze_flow_test.rb` — snooze suppresses push and email; in-app row still created.
   - `test/integration/notification/cooldown_test.rb` — 5 fast mentions → 1 email; second email after 5 min. **Concurrent-jobs case**: enqueue 5 `EmailJob`s in parallel for the same membership and assert exactly one delivery — guards `claim_email_cooldown!`'s atomic-update contract against the read-then-write race.
   - `test/integration/notification/unsubscribe_test.rb` — GET shows confirm page; POST flips `email_when_away` to false; subsequent EmailJob no-ops. SaaS variant: token from workspace A is rejected when used against workspace B; tenant in the signed payload is the only authoritative source.
   - `test/integration/notification/grace_window_revalidation_test.rb` — block toggled mid-window cancels email; message deleted mid-window cancels email; membership revoked mid-window cancels email; account flag flipped mid-window cancels email. Each asserts via the shared `Membership#receives_email_for?` predicate path, no duplicate logic in the job.
   - `test/integration/notification/block_suppression_test.rb` — blocked user mention → no in-app, no push, no email.
3. **SaaS** — `SAAS=true bin/rails test saas/test/` to confirm tenant-scoped token unsubscribe and per-workspace settings isolation.
4. **Manual** — boot `bin/dev`, sign in as two users, exercise:
   - Snooze with each preset; confirm Activity tab still updates (in-app preserved).
   - Flip global `mode` to `nothing` and confirm Activity tab still updates but no push/email fires.
   - Flip per-room `involvement` to `:nothing` and confirm in-app, push, and email are all suppressed for that room.
   - Set room A `involvement` to `:everything` while global `mode: "mentions_and_dms"`, post a non-mention message; confirm push fires (per-room override wins).
   - Change global `mode` with the "Apply to all rooms" checkbox checked; confirm all `Membership#involvement` values update.
   - Flip `email_when_away` on with the feature flag, sign one user out for >10 min, mention them, confirm email arrives ~5 min later (the grace window). Reconnect during the window → no email. Block the sender during the window → no email.
   - Click unsubscribe in the email; confirm `email_when_away` flips to false. SaaS: confirm only the workspace that sent the email is unsubscribed.
   - Verify no behavior change for users who never touch the new settings panel — push and unread badges identical to today.

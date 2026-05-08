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
  └→ Notification::DispatchJob.perform_later(message, activity_type)
        └→ Notification::Dispatcher.dispatch(message:, activity_type:)
              ├→ Notification::Channel::InApp   (creates Notification rows + broadcasts)
              ├→ Notification::Channel::Push    (WebPush via existing pool)
              └→ Notification::Channel::Email   (enqueues Notification::EmailJob with grace window)
```

`activity_type` is a symbol — `:mention`, `:direct_message`, `:everyone_room_message`, `:thread_reply`, `:boost`. **Two of these are dispatcher-only** event types and never produce a `Notification` row: `:direct_message` (push + email channels only — DMs don't create in-app notifications) and `:everyone_room_message` (push channel only). The other three (`:mention`, `:thread_reply`, `:boost`) match the values already stored on `notifications.activity_type` and already in `Notification`'s inclusion validator at `app/models/notification.rb:25`. So **`Notification#validates :activity_type` does NOT change in v1** — the persisted vocabulary stays `%w[mention boost thread_reply]`. The dispatcher's symbol vocabulary is a strict superset used only at routing time. The dispatcher and channels case-switch on the symbol; no parallel class hierarchy.

This matches Fizzy's shape: Fizzy's `Notification::Pushable` does not have an Event class hierarchy either. Its `payload_type` resolves via `source_type.presence_in(%w[ Event Mention ]) || "Default"` — a string lookup at the boundary, not subclass dispatch. Earlier drafts of this plan proposed `Notification::Event::{Mention,DirectMessage,EveryoneRoomMessage,ThreadReply,Boost}` subclasses; dropped because every "subclass override" reduced to either a constant lookup (`IN_APP_TYPES`, `EMAIL_TYPES`) or a one-line recipient query that already exists on `Message`.

| `activity_type` | Recipients (one-line query) | Channels (v1) |
|---|---|---|
| `:mention` | mentionees scoped to `Membership.involved_in_mentions` for the room | in-app, push, email |
| `:direct_message` | `message.room.user_ids` (room is `Rooms::Direct`) | push, email |
| `:everyone_room_message` | `message.room.memberships.involved_in_everything.pluck(:user_id)` | push |
| `:thread_reply` | thread participants (delegated to existing `CreateThreadReplyNotificationsJob`) | in-app, push |
| `:boost` | `[message.boosts.last.message.creator_id]` | in-app |

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

Constants on `Notification::Dispatcher`:

```ruby
ACTIVITY_TYPES = %i[mention direct_message everyone_room_message thread_reply boost].freeze
IN_APP_TYPES   = %i[mention thread_reply boost].freeze
EMAIL_TYPES    = %i[mention direct_message].freeze
```

`records_in_app?(activity_type)` and `email_eligible?(activity_type)` become constant lookups, not method calls on a polymorphic Event.

**Push payload formatting** stays as-is in `Room::MessagePusher#build_payload` (today's `room.direct?` two-branch shape). Fizzy has a `Notification::DefaultPayload` / `EventPayload` / `MentionPayload` hierarchy because each type has substantively divergent rendering (`EventPayload` has a 60-line `case event.action` switch). Sabha's push copy doesn't diverge per activity type today — only by `room.direct?`. **Defer the Payload hierarchy until copy actually diverges per type**; when it does, mirror Fizzy's `Notification::*Payload` shape.

### Layering: global mode vs per-room involvement

Two layers, each with a distinct job. Reconciling them is the whole point of v1:

- **`Membership#involvement`** is the **delivery-time source of truth.** It says whether THIS room delivers `nothing`, only `mentions`, or `everything` for THIS user. Mirrors today's behavior exactly.
- **Global `prefs.mode`** is the **default for new memberships** plus a **master kill switch for outbound channels** (push + email). It does NOT override an explicit per-room `:everything` opt-in. A user who set room A to `:everything` keeps getting all-message push regardless of the global default. Matches Slack: global preference seeds new channels; channel-specific overrides win at delivery.

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

When a user changes mode in the settings panel, the form offers **"Apply to all my rooms"** — checked by default for `nothing` (clear intent), unchecked otherwise (preserve per-room overrides). The bulk update walks `current_user.memberships.visible.without_direct_rooms` and updates `involvement` to match the new default via `User#apply_notification_mode_to_all_rooms!`. Slack's exact pattern.

**`mode: "nothing"` is a kill switch for push and email only.** **In-app rows still get created** so the Activity tab tells the truth on return — same as snooze. To suppress in-app for a specific room, set that room's `involvement` to `:nothing` (per-room is the aggressive control).

### Unread counter consistency

`Message#increment_unread_notifications_counters` (`app/models/message.rb:298`) is a separate `after_create_commit` callback that bumps `Membership#unread_notifications_count` for DMs, `@everyone` messages, and named mentions. **Today it bypasses block checks and `Membership#receives?`** — so a blocked user mentioning me bumps my unread badge even though no `Notification` row, push, or email fires. v1 closes this gap by **moving counter increments into `Notification::Channel::InApp`**, where they share the dispatcher's gate (block, banned, deactivated, room/message active, `membership.receives?`). The `Channel::InApp` step that creates the `Notification` row also bumps the membership counter in the same DB transaction, using the same recipient set. `Message#increment_unread_notifications_counters` is deleted and the `after_create_commit` callback removed from `Message`. This makes "blocked user mention → no in-app" a single invariant rather than a fragile collection of consistent-but-independent checks.

DMs and `@everyone` messages still drive counter bumps even though they don't create `Notification` rows: `Channel::InApp` runs the bump phase for **all** dispatcher recipients, and the row-creation phase only for the subset where `IN_APP_TYPES.include?(activity_type)`. Counter logic is the same as today's: skip senders for non-DM, skip already-connected memberships (`unread_at IS NULL`), only bump rows where `unread_at <= message.created_at`. Verified against the existing implementation; no behavior change for the common path.

### Per-recipient decision tree

`Notification::Dispatcher.decision_for(user:, message:, activity_type:)` is a single class method that returns a `Decision` triple — `EmailJob`'s slim job (via `User#send_notification_email`) calls it again at fire time for revalidation, so the rules can't drift between initial dispatch and delayed delivery.

The return type is a `Data.define` declared inline at the top of the dispatcher class — no separate `recipient_decision.rb` file. A 3-tuple of booleans doesn't earn its own file (Fizzy has no equivalent value object; `Data.define` is the Rails primitive for this exact case):

```ruby
class Notification::Dispatcher
  Decision = Data.define(:in_app, :push, :send_email)
  SKIP     = Decision.new(in_app: false, push: false, send_email: false)

  def self.decision_for(user:, message:, activity_type:)
    return SKIP if user.id == message.creator_id
    return SKIP if user.bot? || !user.active?
    return SKIP if blocked_either_way?(user, message.creator)
    return SKIP unless message.room.active? && message.active?

    membership = membership_for(user, message.room)
    return SKIP if membership.nil? || !membership.active?
    return SKIP unless membership.receives?(activity_type)   # per-room is THE gate

    prefs = user.notification_settings

    # In-app fires whenever the room delivers it. Snooze and global "nothing"
    # do NOT suppress in-app — user gets a record on return.
    in_app = IN_APP_TYPES.include?(activity_type)

    push  = !prefs.snoozed? && prefs.push_enabled? && prefs.mode != "nothing" &&
            !membership.connected?

    email = !prefs.snoozed? && prefs.email_when_away? && prefs.mode != "nothing" &&
            EMAIL_TYPES.include?(activity_type) &&  # Mention + DirectMessage only in v1
            user.email_address.present? && user.verified? &&
            !user.banned? && !user.deactivated? &&
            user_globally_away?(user) &&   # MUST be away at event time
            Sabha.email_notifications?

    Decision.new(in_app: in_app, push: push, send_email: email)
  end
end
```

Callers read `decision.in_app`, `decision.push`, `decision.send_email` — same shape a separate `RecipientDecision` class would have exposed, without the file.

Note that `membership.receives?(activity_type)` is the only delivery-time gate that distinguishes mention events from everyone-room-message events — it's the today's-behavior gate, preserved verbatim. Global `mode` only suppresses when set to `nothing`; mentions/DMs/everyone-messages are not gated by mode otherwise.

Two presence checks:

- **Push** — per-membership `Membership#connected?` (room-scoped, current behavior preserved).
- **Email** — global "away" check across all the user's memberships using `Membership.last_connected_at_for([user.id])` compared against `Membership::Connectable::ACTIVITY_TIERS[:active]` (10 minutes). User is "away for email" if they have no live connection anywhere. **Checked twice**: once at event time inside `Dispatcher.decision_for` (a live reader gets nothing scheduled), and once again at fire time inside `EmailJob` (someone who *was* away at event time but came back during the 5-minute grace window gets nothing sent). Both checks call the same `Dispatcher.decision_for` with the same `(user, message, activity_type)` triple.

The 5-minute grace window scheduled by `EmailJob.perform_later(wait: EMAIL_GRACE_WINDOW)` is the cancellation path. If the user reconnects during the window, the job no-ops at fire time. No active job cancellation needed.

`EMAIL_GRACE_WINDOW = 5.minutes` — chosen to match Slack's "as soon as possible" timing (~5–15 min) and avoid emailing users who just glanced at their phone. Tighter windows (60s) feel engineering-correct but produce noisy false positives for the common "stepped away from the keyboard" case. The cost of a 5-min delay on the rare genuinely-away mention is small; the user wasn't going to read the email for hours anyway.

## Data model

### `User::NotificationSettings` (real AR record)

Direct Fizzy parity — Fizzy's `User::Settings` (`fizzy/app/models/user/settings.rb`) is a real AR record on a `user_settings` table, not a JSON column. The reviewer's earlier `store_accessor`-on-`User` suggestion and the prior PORO-over-`users.preferences` shape were both rejected because v1 already needs the side-effect callbacks AR gives for free (snooze flips that should flush queued mail, mode flips that should bulk-update memberships, `email_when_away: false` flips that revalidate at fire time). Sabha's existing `users.preferences` JSON column is unused today — leave it for unrelated future prefs or drop it later.

```ruby
class User::NotificationSettings < ApplicationRecord
  INDEFINITE_SNOOZE_SENTINEL = Time.utc(2099, 1, 1).freeze

  # Use the repo's hash-mapped string-enum pattern (see app/models/membership.rb:35).
  # Array enum syntax stores integers; Sabha's convention is string columns mapped to themselves.
  enum :mode, %w[ nothing mentions_and_dms all ].index_by(&:itself), default: "mentions_and_dms", prefix: :mode

  belongs_to :user

  SNOOZE_PRESETS = %w[ 1h 4h until_tomorrow indefinite ].freeze

  def snoozed?
    snooze_until.present? && (indefinite_snooze? || snooze_until > Time.current)
  end

  def snooze!(preset)
    update!(snooze_until: resolve_snooze(preset))
  end

  def unsnooze!
    update!(snooze_until: nil)
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

  private
    def indefinite_snooze?
      snooze_until == INDEFINITE_SNOOZE_SENTINEL
    end

    def resolve_snooze(preset)
      case preset
      when "1h"             then 1.hour.from_now
      when "4h"             then 4.hours.from_now
      when "until_tomorrow" then Time.zone.now.tomorrow.beginning_of_day + 8.hours
      when "indefinite"     then INDEFINITE_SNOOZE_SENTINEL
      end
    end
end
```

`mode` is a real Rails enum mapped via the repo's `%w[...].index_by(&:itself)` pattern (matches `Membership#involvement` at `app/models/membership.rb:35`). Three values load-bearing for the default-involvement mapping. Bang methods (`mode_nothing!`) and predicates (`mode_nothing?`) come for free with the `prefix: :mode` option. The channel toggles are booleans because there are only two meaningful states each. We initially considered three-state `push_mode` (`always` / `when_away` / `never`) but `always` is a fake state — pushing while the user is actively reading the room is bad UX, no app does it, and the underlying decision tree only has two states regardless of UI labels.

**Snooze sentinel**: `INDEFINITE_SNOOZE_SENTINEL = Time.utc(2099, 1, 1)` — far-future timestamp checked explicitly in `snoozed?`. Keeps the column type a real `datetime`, avoids `null`-as-special-value confusion (null = not snoozed, sentinel = forever, real timestamp = snoozed until). `Time.zone.now` (Rails-set application timezone) drives `until_tomorrow` resolution; per-user timezone is out of scope (no `users.time_zone` column today; revisit when we add user TZ).

`User` association + delegates:

```ruby
class User < ApplicationRecord
  has_one :notification_settings, class_name: "User::NotificationSettings", dependent: :destroy
  after_create_commit :create_default_notification_settings!,
    unless: -> { notification_settings.present? }

  delegate :snoozed?, :snooze!, :unsnooze!, :mode, :email_when_away?, :push_enabled?,
           :default_involvement_for_new_membership, to: :notification_settings

  def apply_notification_mode_to_all_rooms!
    new_involvement = notification_settings.default_involvement_for_new_membership
    memberships.visible.without_direct_rooms.update_all(involvement: new_involvement)
  end

  private
    def create_default_notification_settings!
      # has_one's generated build_*/create_* helper. Persists with column defaults
      # (mode: "mentions_and_dms", email_when_away: false, push_enabled: true).
      create_notification_settings!
    end
end
```

`apply_notification_mode_to_all_rooms!` is a `User` method (operates on `user.memberships`), not on the settings record. Called from the settings controller when the "Apply to all my rooms" checkbox is checked.

Unsubscribe tokens are NOT generated via `generates_token_for` — that primitive can't carry tenant identity, which SaaS requires (see Email pipeline § Unsubscribe). Tokens are minted via `Rails.application.message_verifier(:email_unsubscribe)` with a `{ user_id, tenant }` payload and a 1-month expiry (CAN-SPAM compliant, avoids dead-link permanence — pattern adapted from Fizzy's `User::Notifiable`).

### Migrations

Three migrations in v1:

```ruby
create_table :user_notification_settings do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.string  :mode,             null: false, default: "mentions_and_dms"
  t.boolean :email_when_away,  null: false, default: false
  t.boolean :push_enabled,     null: false, default: true
  t.datetime :snooze_until                                # null = not snoozed; INDEFINITE_SENTINEL = forever
  t.timestamps
end

add_column :memberships, :last_email_notified_at, :datetime
add_column :accounts,    :email_notifications_enabled, :boolean, default: false, null: false
```

- `user_notification_settings` — one row per user, built on user creation. Real columns get real Rails affordances: `enum :mode` with bang methods, dirty tracking, AR callbacks, `saved_change_to_*?`, query scopes. **Backfill on deploy**: a small data migration (or `User.find_each(&:create_notification_settings!)`) seeds existing users with a settings row using the column defaults — `mode: "mentions_and_dms"`, `email_when_away: false`, `push_enabled: true`. Zero behavior change because the defaults reproduce today's gates.
- `memberships.last_email_notified_at` — per-user-per-room cooldown anchor. Read on every event, written on every email send. 5-minute cooldown enforced via `Membership#recently_emailed?` (`Membership::EMAIL_COOLDOWN = 5.minutes`); the bang verb `Membership#record_email_delivery!` writes the timestamp. Cooldown logic lives on the model where the column lives, not on the job. Composite `(user_id, room_id)` index already exists; no new index needed.
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

Both mailers `include Mailers::Unsubscribable` (pattern lifted from Fizzy at `app/mailers/concerns/mailers/unsubscribable.rb`) — a six-line concern that adds RFC 8058 headers via `after_action`:

```ruby
module Mailers::Unsubscribable
  extend ActiveSupport::Concern
  included do
    after_action :set_unsubscribe_headers
  end
  def set_unsubscribe_headers
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    headers["List-Unsubscribe"]      = "<#{email_unsubscribes_url(token: @unsubscribe_token)}>"
  end
end
```

Each mailer method mints `@unsubscribe_token` via `Rails.application.message_verifier(:email_unsubscribe).generate({ user_id: user.id, tenant: ApplicationRecord.current_tenant }, expires_in: 1.month, purpose: :email_unsubscribe)` (full shape in the Unsubscribe subsection below). The concern handles the rest. **Do not use `User#generate_token_for(:email_unsubscribe)` — that primitive can't carry tenant identity, which SaaS requires.** Centralizing the token mint in a small mailer helper (e.g. `def unsubscribe_token_for(user); ...; end` on `ApplicationMailer`) avoids drift across mailers.

Templates render `message.plain_text_body.truncate(280)`, a CTA link to `room_at_message_url(room, message)`, "Manage notifications" link to the settings panel, and an in-body unsubscribe link (the human path; the header is the MUA path).

**Job** (`app/jobs/notification/email_job.rb`) — scheduled with `wait: Notification::EmailJob::EMAIL_GRACE_WINDOW` (5 minutes). Declares `discard_on ActiveJob::DeserializationError` (mirroring `app/jobs/room/push_message_job.rb`) so a message or membership deleted during the grace window cleanly drops the job rather than retrying. Same pattern on `Notification::DispatchJob`. At fire time the job is a **shallow wrapper** that delegates to `User#send_notification_email` — substance lives on the model where the data lives, per the DHH "jobs are shallow wrappers calling model methods" pattern (`architecture.md` § background_jobs). The model method **re-runs the dispatcher's full decision** rather than duplicating a subset of checks, so state changes during the grace window (block toggled, message deleted, room destroyed, account flag flipped, membership revoked) all flow through the same gate that approved the dispatch.

```ruby
# app/jobs/notification/email_job.rb
class Notification::EmailJob < ApplicationJob
  EMAIL_GRACE_WINDOW = 5.minutes

  discard_on ActiveJob::DeserializationError

  def perform(user, message, activity_type)
    return if DemoMode.enabled?
    user.send_notification_email(message, activity_type)
  end
end

# app/models/user.rb (added)
def send_notification_email(message, activity_type)
  return unless Notification::Dispatcher.decision_for(
    user: self, message: message, activity_type: activity_type
  ).send_email

  membership = memberships.find_by(room_id: message.room_id)
  return if membership.nil? || membership.recently_emailed?

  case activity_type
  when :mention        then UserMailer.mention_notification(self, message).deliver_now
  when :direct_message then UserMailer.direct_message_notification(self, message).deliver_now
  end
  membership.record_email_delivery!
end

# app/models/membership.rb (added)
EMAIL_COOLDOWN = 5.minutes

def recently_emailed?
  last_email_notified_at.present? && last_email_notified_at > EMAIL_COOLDOWN.ago
end

def record_email_delivery!
  update_column(:last_email_notified_at, Time.current)
end
```

`return unless user && message` is dropped — `discard_on ActiveJob::DeserializationError` already handles the missing-record case, matching `Room::PushMessageJob` exactly. The `EMAIL_GRACE_WINDOW` constant stays on the job (it controls `wait:`, a job-runtime concern); `EMAIL_COOLDOWN` lives on `Membership` because the cooldown is a business policy on the room-level relationship, not job runtime. Cooldown read/write are predicate + bang verb on `Membership` — `recently_emailed?` and `record_email_delivery!`.

The `Notification::DispatchJob` follows the same shape and adds the standard `_later`/`_now` symmetry from `architecture.md`:

```ruby
# app/models/message.rb (added)
def notify_recipients(activity_type)
  Notification::Dispatcher.dispatch(message: self, activity_type: activity_type)
end

def notify_recipients_later(activity_type)
  Notification::DispatchJob.perform_later(self, activity_type)
end

# app/jobs/notification/dispatch_job.rb
class Notification::DispatchJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(message, activity_type)
    return if DemoMode.enabled?
    message.notify_recipients(activity_type)
  end
end
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

`:boost` does not flow through `Room#notify_later` — it's triggered by a boost-creation event, dispatched separately (see Reuse note: existing boost-creation path adopts `notify_recipients_later(:boost)`).

Public surface is `message.notify_recipients_later(activity_type)` — same shape as Campfire's `notify_watchers_later`. The N-jobs-per-message design keeps the dispatcher's per-call work narrow (one decision tree pass per (recipient, activity_type)) and lets us schedule per-channel work independently.

Test surface moves with the logic: `User#send_notification_email`, `Membership#recently_emailed?`/`#record_email_delivery!`, and `Message#notify_recipients` get tested where they live; the job tests collapse to "do I delegate?" — minimal coverage, since substance is tested on the models.

**Email-at-event-time semantics**: `EmailJob` is scheduled **only if the user is already globally away when the event fires** (`user_globally_away?` returns true at dispatch). A user actively reading the chat at the moment of mention sees the message live and gets no email queued — they didn't miss it. The grace window is purely a *cancellation* mechanism for the case "user was away at event time but came back during the 5 minutes before delivery", not a *capture-on-departure* mechanism for "user was online but might drift offline soon". Without the at-dispatch check, a live reader who closes their laptop 4 minutes after seeing a mention would still get an email about it — wrong product behavior, and inconsistent with Slack / Google Chat / every other chat app.

If the user was online at event time and goes offline ten minutes later, they get nothing for that earlier mention. They'll see it in-app on return (Activity tab + unread badge). This is the deliberate tradeoff: in-app is the truth-on-return surface; email is for "I wasn't there when it happened".

**Job arguments are records (plus the activity_type symbol), not raw IDs.** `EmailJob.perform_later(user, message, activity_type)` and `DispatchJob.perform_later(message, activity_type)` pass tenanted records directly. Per `activerecord-tenanted`, ActiveJob captures the current tenant at enqueue and restores it at perform; tenanted GlobalIDs additionally bind tenant into the serialized argument. Belt-and-suspenders. Raw IDs would bypass the GlobalID layer and rely solely on the tenant-set-at-enqueue belt — silent corruption risk if anyone calls `EmailJob.perform_now(123, 456, :mention)` outside a tenant context. With record arguments, the GlobalID locator refuses to load cross-tenant.

### Mailer URL helpers (SaaS path-based tenancy)

The activerecord-tenanted gem documents subdomain interpolation (`%{tenant}` in `default_url_options[:host]`) but explicitly defers path-based and explicit-host helpers — see `docs/multi-tenant/activerecord-tenanted-guide.md` lines 720–724. Sabha SaaS uses **path-based** tenanting (workspace prefix in the URL). The mention/DM email's CTA link to `room_at_message_url(room, message)` must include the workspace path prefix or it 404s in SaaS.

**Action before implementation**: research how the existing SaaS mailers (`saas/app/mailers/auth_code_mailer.rb`, `saas/app/mailers/workspace_mailer.rb`) render workspace-prefixed URLs and reuse that pattern in `UserMailer#mention_notification` / `direct_message_notification`. Most likely it's a `script_name` set in the mailer's URL options; document the exact mechanism in the implementation PR.

**The unsubscribe URL is workspace-prefix-free** — it lives at top-level (no tenant in path), and the signed token's `{ user_id, tenant }` payload carries tenancy. Different shape from the in-app CTA URL on purpose.

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
      User.find(payload[:user_id]).notification_settings.update!(email_when_away: false)
    end
    head :ok
  end
end
```

The `allow_unauthenticated_access` class method already exists on `Authentication` (no need to invent it). `skip_forgery_protection` is scoped to `create` only — the GET confirmation page is safe under default protection. Rate limit (Rails 8 `rate_limit`) prevents token-spray abuse even though the signed payload itself is the gatekeeper.

**Token shape — tenant-bound `MessageVerifier`, not `generates_token_for`.** `generates_token_for` can't carry a workspace identifier in the payload, and SaaS requires the controller to enter the right tenant *before* loading the user (`User` is tenanted, so cross-tenant lookups can't happen safely). The plan uses `Rails.application.message_verifier` directly:

```ruby
# Generation (in mailer, while inside the tenant)
@unsubscribe_token = Rails.application.message_verifier(:email_unsubscribe).generate(
  { user_id: user.id, tenant: ApplicationRecord.current_tenant },
  expires_in: 1.month, purpose: :email_unsubscribe
)

# Validation (in controller, no tenant yet)
payload = Rails.application.message_verifier(:email_unsubscribe).verified(
  params[:token], purpose: :email_unsubscribe
)
return head :not_found unless payload
ApplicationRecord.with_tenant(payload[:tenant]) do
  user = User.find(payload[:user_id])
  user.notification_settings.update(email_when_away: false)
  # render confirmation
end
```

The signed payload binds user-id and tenant together — a token from workspace A can't be reused against workspace B's user with the same id, and an attacker can't substitute the tenant outside the signature. 1-month expiry satisfies CAN-SPAM and avoids dead-link permanence. Self-hosted mode passes `tenant: nil` and the `with_tenant` block degrades to a no-op (`activerecord-tenanted` handles this).

**Feature flag**: `Sabha.email_notifications?` — true when `ENV["SABHA_EMAIL_NOTIFICATIONS"] == "1"` OR `Account.sole.email_notifications_enabled?` (column added in this v1's migrations — see Data model § Migrations). Defined on the existing top-level `Sabha` module (`lib/sabha.rb`), parallel to the existing `Sabha.saas?` predicate — same shape, same precedent. Lets us ship dark and turn on per-account/tenant before flipping the env default.

## Snooze UX

Single `snooze_until` `datetime` column on `user_notification_settings`. `INDEFINITE_SENTINEL` (a far-past timestamp like `Time.at(0)`, checked explicitly in `snoozed?`) marks indefinite snooze — keeps the column type consistent and avoids `null`-as-special-value confusion.

Quick toggle in the sidebar bell icon (`app/views/users/sidebars/_bell.html.erb`) opens a popover with presets. Stimulus controller `app/javascript/controllers/snooze_controller.js` posts to `users/notification_snoozes` (new singular resource).

Full controls live in the new Notifications section of the profile.

`"until_tomorrow"` resolves to **next 8 AM in `Time.zone`** (the application's configured `Rails.application.config.time_zone`). There is no `users.time_zone` or `accounts.time_zone` column today (verified against `db/schema.rb`); per-user TZ resolution is out of scope and revisited if a user-TZ column lands.

What snooze suppresses: **push + email**. **In-app rows still get created** so the Activity tab shows what was missed on return.

## Settings UI

New partial `app/views/users/profiles/_notifications.html.erb`, rendered above the existing memberships fieldset in `app/views/users/profiles/show.html.erb`. The per-room involvement loop moves under a `<h3>Per-room overrides</h3>` subhead inside the new fieldset.

Sections, top to bottom:

1. **Mode** — radio group: All messages / Mentions and DMs / Nothing. Helper text clarifies semantics: "This is the default for rooms you join. Each room can be overridden below." Below the radios, a checkbox: **"Also apply to all my existing rooms"** — pre-checked when the user picks `Nothing` (clear intent), unchecked otherwise. On submit, if checked, `User#apply_notification_mode_to_all_rooms!` walks `current_user.memberships.visible.without_direct_rooms` and updates each `involvement` to the mapping in the layering table.
2. **Snooze** — current state ("Snoozed until 5pm" or "Off"), preset buttons, "Turn off snooze" when active.
3. **Email** — single toggle: "Email me about mentions and DMs when I'm away". Disabled state with explanation copy when the feature flag is off for this account.
4. **Push** — single toggle: "Push notifications". Plus the existing device list (move `app/views/users/push_subscriptions/index.html.erb` content inline). No three-state — push fires when the membership is disconnected from the room, period; the toggle is on/off.
5. **Per-room overrides** — existing `_membership.html.erb` loop, unchanged. Helper text: "Overrides your default for individual rooms."

New routes (in `config/routes.rb`, scoped under `users/me`):

```ruby
resource :notification_settings, only: %i[update]
resource :notification_snooze,   only: %i[create destroy]
```

Plus top-level: `resources :email_unsubscribes, only: %i[show create], param: :token`. **Registered outside any tenant routing constraint** (peer of `/session/new`, `/workspaces`) so the controller can decode the signed token before the middleware needs to resolve a tenant from the URL. The token's `{ user_id, tenant }` payload is the sole source of tenancy for this route. The controller is `EmailUnsubscribesController` (no `Users::` namespace) since it is not user-scoped — it's accessed unauthenticated by token from outside the app.

## Files

### Namespace

All new classes hang off the existing `Notification` model — `Notification::Dispatcher`, `Notification::Channel::*`, `Notification::DispatchJob`, `Notification::EmailJob`, etc. Direct parity with Fizzy, which uses `Notification::Pushable`, `Notification::PushTarget::Web`, `Notification::Bundle`, `Notification::*Payload`. Earlier drafts used `Notifications::` (plural) as an invented top-level namespace — dropped. `CLAUDE.md` mandates namespace decomposition off existing models (`User::Role`, `Message::Searchable`, `Room::MessagePusher`); singular `Notification::` satisfies that and matches Fizzy verbatim. Rejected `Message::Notifier` (suggested by review) because the new code includes channels (`Channel::Push`, `Channel::Email`) and a job (`EmailJob`) that aren't naturally about a Message — they're about a notification-worthy event delivered through a transport.

### New

- `app/models/user/notification_settings.rb` — real AR record on the new `user_notification_settings` table. Direct Fizzy parity with `User::Settings`. `enum :mode`, three boolean/datetime columns, `belongs_to :user`. AR callbacks (`saved_change_to_*?`) replace hand-rolled mutators.
- `app/models/notification/dispatcher.rb` — routing brain. Class methods `dispatch(message:, activity_type:)` and `decision_for(user:, message:, activity_type:)`. Constants `ACTIVITY_TYPES`, `IN_APP_TYPES`, `EMAIL_TYPES`. **No Event class hierarchy** — `activity_type` is a symbol that matches the existing `notifications.activity_type` column. Recipient queries are case-switched on the symbol; each case is a one-liner using existing scopes/methods on `Message` and `Membership`. (Earlier draft proposed `Notification::Event::{Mention,DirectMessage,EveryoneRoomMessage,ThreadReply,Boost}` subclasses — dropped because Fizzy's `Notification::Pushable` uses string lookup at the boundary, not subclass dispatch, and every "subclass override" in the draft reduced to a constant lookup or an existing one-line query.)
- `app/models/notification/channel/email.rb`, `app/models/notification/channel/in_app.rb`.
- `app/models/notification/channel/push.rb` — facade that fans out to registered push targets. **Direct parity with Fizzy's shipped `Notification::Pushable` concern** (`fizzy/app/models/notification/pushable.rb`), which exposes `register_push_target(:web)` and iterates `push_targets.each { |target| push_to(target) }`. This is not a speculative abstraction — it's the same registration shape Fizzy runs in production today, ported to Sabha's namespace.
- `app/models/notification/channel/push/web.rb` — WebPush delivery, mirroring Fizzy's `Notification::PushTarget::Web` (`fizzy/app/models/notification/push_target/web.rb`) which queues to `Rails.configuration.x.web_push_pool`. The base class shape (`Notification::PushTarget` with `self.process(notification)` + instance `process`) is also lifted directly. **Native APNs and FCM are roadmap items for Sabha mobile**, and Fizzy's structure is what we'll plug `::Apns` / `::Fcm` siblings into when we ship — same as Fizzy will. Naming the v1 implementation `::Web` is required for that registration to make sense, not future-proofing for its own sake.
- `app/mailers/concerns/mailers/unsubscribable.rb` — RFC 8058 header concern (lifted verbatim from Fizzy at `fizzy/app/mailers/concerns/mailers/unsubscribable.rb` — 6 lines of body, identical shape). v1 has one caller (`UserMailer`'s mention/DM methods), matching Fizzy's current single-caller setup. v1.1's deferred `Notification::BundleMailer` (digests, see Out of scope § Deferred) becomes the second caller, mirroring Fizzy's `Notification::BundleMailer` exactly. Keeps `CLAUDE.md`'s "don't extract small chunks" rule satisfied once the second caller lands and avoids re-extracting then.
- `app/jobs/notification/dispatch_job.rb` — replaces `Room::PushMessageJob`. Shallow wrapper: `def perform(message, activity_type) = (return if DemoMode.enabled?; message.notify_recipients(activity_type))`. `discard_on ActiveJob::DeserializationError`.
- `app/jobs/notification/email_job.rb` — shallow wrapper: `def perform(user, message, activity_type) = (return if DemoMode.enabled?; user.send_notification_email(message, activity_type))`. Defines `EMAIL_GRACE_WINDOW = 5.minutes` (job-runtime concern). `discard_on ActiveJob::DeserializationError`.
- `app/views/user_mailer/{mention_notification,direct_message_notification}.{html,text}.erb`.
- `app/views/users/profiles/_notifications.html.erb`.
- `app/controllers/users/notification_settings_controller.rb`.
- `app/controllers/users/notification_snoozes_controller.rb`.
- `app/controllers/email_unsubscribes_controller.rb`.
- `app/javascript/controllers/snooze_controller.js`.
- `db/migrate/YYYYMMDDHHMMSS_create_user_notification_settings.rb` (+ a follow-up backfill migration that runs `User.find_each(&:create_notification_settings!)` to seed existing users with column defaults).
- `db/migrate/YYYYMMDDHHMMSS_add_last_email_notified_at_to_memberships.rb`.
- `db/migrate/YYYYMMDDHHMMSS_add_email_notifications_enabled_to_accounts.rb`.

### Modify

- `app/mailers/user_mailer.rb` — add `mention_notification`, `direct_message_notification`.
- `app/models/user.rb` — `has_one :notification_settings` association, `after_create_commit` default-build hook (`create_notification_settings!`), snooze/mode delegates, `apply_notification_mode_to_all_rooms!` instance method. **Add `send_notification_email(message, activity_type)` instance method** that re-runs `Notification::Dispatcher.decision_for`, gates on `Membership#recently_emailed?`, and dispatches to the right `UserMailer` method (logic moved off `Notification::EmailJob` for shallow-job parity). Update `destroy_all_associated_records` to include the new `notification_settings` association.
- `app/models/room.rb` — (1) `#push_later` → `#notify_later`. `#notify_later` enqueues **one `Notification::DispatchJob` per applicable activity_type** (a single message can fire both `:everyone_room_message` and `:mention`; STI subclasses override `#applicable_activity_types` to narrow the set). (2) Add `#applicable_activity_types(message)` returning `[:everyone_room_message]` plus `:mention` when the message has mentions — base behavior for open/closed rooms. (3) `Room#default_involvement(user:)` reads from `user&.notification_settings&.default_involvement_for_new_membership` with `"mentions"` fallback.
- `app/models/rooms/direct.rb` — override `#applicable_activity_types(_message) = [:direct_message]`. `#default_involvement` stays unchanged so DMs always seed as `"everything"`.
- `app/models/rooms/thread.rb` — override `#applicable_activity_types(_message) = [:thread_reply]`.
- `app/models/message.rb` — remove `create_mention_notifications` body; logic moves to `Notification::Channel::InApp`. **Also remove `increment_unread_notifications_counters` and its `after_create_commit` callback** — counter bumps move into `Channel::InApp` so they share the dispatcher's block/receives? gates (see Architecture § Unread counter consistency). The reactivation path (`restore_unread_notifications_counters_if_reactivated`) stays where it is for now — it's a console/admin path that doesn't go through the dispatcher. **Add `notify_recipients(activity_type)` and `notify_recipients_later(activity_type)` instance methods** — the public API for dispatching notifications about a message; `Notification::DispatchJob` is a shallow wrapper that calls `message.notify_recipients(activity_type)`. **Preserve the `[user, :inbox_activity]` stream-key form** in all `broadcast_*_to` calls — bare symbol streams collide across tenants per the activerecord-tenanted gem's GlobalID guarantees (Sabha team note in `docs/multi-tenant/activerecord-tenanted-guide.md` line 664).
- `app/models/membership.rb` — (1) Add `receives?(activity_type)` that wraps `receives_mentions?` + `:everything` semantics. (2) **Add `EMAIL_COOLDOWN = 5.minutes` constant + `recently_emailed?` predicate + `record_email_delivery!` bang method** — the email-cooldown business policy lives where `last_email_notified_at` lives, off the job per DHH "jobs are shallow wrappers" pattern.
- `app/views/users/profiles/show.html.erb` — render new partial; move per-room loop under it.
- `app/views/users/sidebars/_bell.html.erb` — snooze quick toggle.
- `config/routes.rb` — new resources.
- `lib/sabha.rb` — add `Sabha.email_notifications?` predicate (parallel to existing `Sabha.saas?`).

### Reuse (do not reinvent)

- `Membership::Connectable` — presence (`connected?`, `disconnected` scope, `last_connected_at_for`, `ACTIVITY_TIERS`).
- `Rails.configuration.x.web_push_pool` — push delivery pool.
- `User#blocked?` / `User#blocked_by?` — block check.
- `Branding.mailer_from` and existing mailer layouts.
- `Notification` model — Dispatcher creates rows through it, schema unchanged.

### Delete (after Dispatcher is proven)

- `app/models/room/message_pusher.rb` — folded into `Notification::Channel::Push`.
- `app/jobs/room/push_message_job.rb` — replaced by `Notification::DispatchJob`.

## Rollout

1. Run migrations: `SAAS=true bin/rails db:migrate:primary` in SaaS (auto-runs against every tenant per the activerecord-tenanted gem's database tasks) or `bin/rails db:migrate` for self-hosted. Then ship the Dispatcher with `Sabha.email_notifications?` returning false everywhere (env unset, all `accounts.email_notifications_enabled` columns default to false). Push and in-app behavior unchanged because the Dispatcher reproduces today's `MessagePusher` matrix exactly under the default settings.
2. Run the existing test suite plus the new Dispatcher tests to confirm regression-free push behavior.
3. Enable the email path for one test account by setting `Account#email_notifications_enabled = true` inside that workspace's tenant context.
4. Watch sender domain reputation, bounce rates, and cooldown effectiveness in staging.
5. Toggle on per-account in production, then flip the env default and remove the flag.

Existing-user defaults at deploy: the backfill migration creates one `user_notification_settings` row per existing `User` using the column defaults — `mode: "mentions_and_dms"`, `push_enabled: true`, `email_when_away: false`, `snooze_until: nil`. **Zero behavior change** at deploy — `mode` only seeds defaults for *future* memberships, so existing per-room `Membership#involvement` values (including `:everything`) deliver exactly as they do today. Push respects today's per-membership disconnected check. Email is feature-flagged off.

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

## Risks and confirmed decisions

- **Layering of global mode vs per-room involvement** — confirmed: per-room `Membership#involvement` is the delivery-time gate; global `mode` only seeds defaults for new memberships and acts as a kill switch when set to `nothing`. A user with global `mentions_and_dms` and room `involvement: :everything` keeps getting all-message push. Settings UI offers an opt-in "Apply to all my rooms" checkbox when changing the global mode.
- **`mode: "nothing"` semantics** — confirmed: suppresses outbound channels (push, email) only; in-app rows still fire so the Activity tab tells the truth on return. Same shape as snooze. Per-room `involvement: :nothing` is the aggressive option for "don't even badge me for this room".
- **Block suppression** — confirmed: blocks suppress push, email, and in-app for messages from the blocked user. Mention notification rows are NOT created. Implement via `User#blocked?` / `User#blocked_by?` check inside Dispatcher.
- **Email default for existing users** — confirmed: `email_when_away: false`. Opt-in via the new settings panel. Avoids surprise emails for users who deliberately got rid of email when `mailkick` was removed.
- **Unsubscribe pattern** — confirmed: two-step (GET confirmation page + POST flip). Defends against email-client GET prefetchers.
- **Banned/deactivated guard** — explicit early return in `EmailJob`.
- **DemoMode** — replicate the existing `Room::PushMessageJob` early return in `Notification::DispatchJob`.
- **Tenant resolution for unsubscribe links in SaaS** — solved via `Rails.application.message_verifier(:email_unsubscribe)` with `{ user_id, tenant }` payload (see Email pipeline § Unsubscribe). `generates_token_for` is intentionally not used here because it can't bind tenant.
- **Global rate limit** — beyond the 5-minute per-room cooldown, no global per-user cap in v1. If 50 simultaneous mentions across rooms generate 50 emails, accept that. Revisit if abused.
- **Cooldown for DMs** — same 5-minute per-room cooldown applies. A DM room is one room.

## Verification

1. **Unit** — `bin/rails test test/models/user/notification_settings_test.rb test/models/notification/dispatcher_test.rb test/jobs/notification/email_job_test.rb test/mailers/user_mailer_test.rb`. Dispatcher test is a parameterized matrix over `mode × involvement × push_enabled × email_when_away × snoozed × connected_membership × global_active × event_type × blocked` — about 30 representative rows asserting the `(in_app, push, email)` triple. Must explicitly cover: user with `mode: mentions_and_dms` + room `involvement: :everything` → all-message push fires (regression case from initial review).
2. **Integration**:
   - `test/integration/notification/mention_email_flow_test.rb` — mention → DispatchJob → grace window → EmailJob → mail delivered when offline; no mail when connected anywhere.
   - `test/integration/notification/snooze_flow_test.rb` — snooze suppresses push and email; in-app row still created.
   - `test/integration/notification/cooldown_test.rb` — 5 fast mentions → 1 email; second email after 5 min.
   - `test/integration/notification/unsubscribe_test.rb` — GET shows confirm page; POST flips `email_when_away` to false; subsequent EmailJob no-ops. SaaS variant: token from workspace A is rejected when used against workspace B; tenant in the signed payload is the only authoritative source.
   - `test/integration/notification/grace_window_revalidation_test.rb` — block toggled mid-window cancels email; message deleted mid-window cancels email; membership revoked mid-window cancels email; account flag flipped mid-window cancels email. Each asserts via the shared `Notification::Dispatcher.decision_for` path, no duplicate logic in the job.
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

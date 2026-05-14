# Sabha notifications architecture

**Status:** Draft (2026-05-09).
**Area:** All notification channels — in-app rows, push, missed-notification email (bundled), weekly activity digest email.
**Source of truth for:** structure, components, and data shapes. Detailed implementation steps live in a separate plan to be authored against this doc.
**Related:**

- `docs/plans/email-notifications/EMAIL-NOTIFICATIONS-PRD.md` — product scope this doc serves.
- `docs/plans/email-notifications/NOTIFICATIONS-SLACK-COMPARISON.md` — competitive framing.
- `docs/plans/email-notifications/UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md` — superseded V0 draft. Kept for routing/eligibility background; do not implement from it.

---

## 1. Goals (architectural)

1. **One dispatcher** decides what fires per recipient per event across all channels. No more split decision trees in `Room::MessagePusher`, `Message` callbacks, and "email nowhere."
2. **Bundled missed-notification email** instead of per-event delayed sends. Hourly or daily bundles, user-selectable.
3. **Separate weekly digest pipeline.** Different copy, different cadence, different opt-out, different gates. It is not a degenerate bundle.
4. **Send-time revalidation** is the cancellation path. State changes during a bundle window (return, block, delete, opt-out) drop items at delivery time.
5. **Tenant-safe by construction.** Per-workspace settings, per-workspace bundles, per-workspace digest. Identity and email address are the only untenanted touchpoints.
6. **Default safe.** Email feature-flagged off at the workspace level. Both email surfaces default off for users.

## 2. Channels

| Channel | Trigger | Storage |
|---|---|---|
| In-app row | Per-message, when activity_type creates a `Notification` row | `notifications` table (existing) |
| Push (WebPush) | Per-message, when membership is push-eligible and disconnected | `push_subscriptions` (existing) |
| Missed-notification email | Per-message, eligible items accumulate into a per-user bundle and deliver hourly/daily | `notification_bundles` + `notification_bundle_items` (new) |
| Weekly activity digest email | Recurring per-workspace job, generated content for opted-in members | No persistent store; `last_digest_sent_at` per user for dedup |

Channels are independent. A user can be a row recipient and not a push recipient; a bundle item and not a digest recipient.

## 3. Activity types

Dispatcher symbol vocabulary (used at routing time only — does not all map 1:1 to persisted `Notification.activity_type` values):

| `activity_type` | Channels (v1) |
|---|---|
| `:mention` (incl. `@everyone`) | in-app row, push, missed-notification email |
| `:direct_message` | push, missed-notification email |
| `:everyone_room_message` | push |
| `:thread_reply` | in-app row, push |
| `:boost` | in-app row |

`:direct_message` and `:everyone_room_message` are dispatcher-only — they never produce `Notification` rows. The persisted `Notification#activity_type` vocabulary stays `%w[mention boost thread_reply]`. The dispatcher's symbol set is a strict superset used only at routing time.

Out of scope for email in v1: `:thread_reply` (deferred — see § 13), `:boost` (no precedent in Slack/Discord; not planned), regular room messages. Encoded by `Notification::Routing::EMAIL_TYPES = %i[mention direct_message]`.

**Routing vocabulary lives on `Notification::Routing`**, not on `Membership::Notifiable`. The matrix above is encoded as constants on a small module:

```ruby
module Notification::Routing
  ACTIVITY_TYPES   = %i[mention direct_message everyone_room_message thread_reply boost].freeze
  IN_APP_ROW_TYPES = %i[mention thread_reply boost].freeze
  PUSH_TYPES       = %i[mention direct_message everyone_room_message thread_reply].freeze
  EMAIL_TYPES      = %i[mention direct_message].freeze
end
```

`Membership::Notifiable` predicates *reference* these constants — they do not own them. Membership is the recipient context; what activity types route to which channels is routing-vocabulary, not membership state. Adding a fifth channel (or a new activity type) edits `Notification::Routing` first, then the predicate that consumes it.

## 4. Eligibility — `Membership::Notifiable`

A single concern on `Membership` answers per-channel eligibility for a given `(message, activity_type)` pair. The same predicates run at dispatch time and at delivery time, so state changes flow through one gate.

Per-channel predicates:

- `receives_in_app_row_for?(message, activity_type)`
- `receives_push_for?(message, activity_type)`
- `receives_missed_email_for?(message, activity_type)`
- `receives_digest?` *(no message argument — digest eligibility is per-membership, not per-message)*

Common gates (apply to all channels):

- Recipient is not the message creator (except for `:direct_message` accounting).
- Recipient is active, verified, not banned, not deactivated, not a bot.
- Recipient and sender are not blocked in either direction.
- Message and room are active.
- Membership is active and **`effective_involvement`** authorizes this `activity_type`.

**`Membership#effective_involvement`** is the single method that answers "what is this membership's true involvement after applying the global mode override?" Predicates ask `effective_involvement` only; they do not read `mode` and `involvement` independently. Rule:

1. If per-room `involvement == "everything"` → effective is `"everything"` (per-room opt-in beats global mute).
2. Else if global `mode == "nothing"` → effective is `"nothing"` (global mute applies).
3. Else → effective is the per-room `involvement` (`mentions` / `nothing` / `invisible`).

Folding the two-source rule into one method removes the per-call-site foot-gun where a predicate could check `mode` and `involvement` in the wrong order, or check one and forget the other. `receives?(activity_type)` reads from `effective_involvement` only.

Channel-specific gates:

- **Push:** `user.push_enabled?`, membership not currently `connected?`.
- **Missed-notification email:** `user.missed_email_enabled?`, account email flag on, `user.workspace_locally_away?`, `activity_type.in?(Notification::Routing::EMAIL_TYPES)`.
- **Weekly digest:** `user.weekly_digest_subscribed?`, account `weekly_digest_enabled?`.

**Two distinct presence checks:** push uses per-membership `connected?` (room-scoped, 60-second WebSocket TTL); email uses `workspace_locally_away?` (queries `Membership.last_connected_at_for([id])` against the **`:away` activity tier — 1 hour** — workspace-local, not cross-workspace).

`workspace_locally_away?` returns true when the user's most recent connection in any of this workspace's memberships is more than `Membership::Connectable::ACTIVITY_TIERS[:away]` (1 hour) ago, or never. The `:away` tier is chosen over the tighter `:active` tier (10 minutes) because email is asking a different question than UI presence: not "should we show a green dot" but "has the user been gone long enough that an email is the right way to reach them?" A brief mid-window visit (e.g. user pops in for 2 minutes during an hourly bundle) means the user could plausibly have seen the message live, so the bundle should drop at delivery time. Using the 10-minute tier would email those users; using the 1-hour tier does not.

**Snooze / DND is not a v1 feature, in any form** (per `EMAIL-NOTIFICATIONS-PRD.md` § Confirmed decisions #7). No `snooze_until` column, no `snooze_indefinite` flag, no presence-as-snooze fallback beyond `workspace_locally_away?`. Implementers should not reach for V0's snooze columns (Appendix A.1) or add new snooze hooks. All "user is unavailable" suppression rides on `workspace_locally_away?` (passive presence) and the per-channel master switches (`missed_email_enabled`, `push_enabled`).

## 5. Routing dispatcher

```
Message create / thread reply
       │
       ▼
Notification::DispatchJob.perform_later(message)
       │
       ▼
Message#notify_recipients
       │
       ▼
For each activity_type in Room#applicable_activity_types(message):
       ├──▶ create_notification_rows_for(activity_type)        (in-app)
       ├──▶ deliver_push_for(activity_type)                    (push)
       └──▶ enqueue_missed_email_candidates_for(activity_type) (bundle add)

(Weekly digest is independent — see § 9.)
```

**One job per message**, not one job per `(message, activity_type)` pair. The job is a shallow wrapper that calls `message.notify_recipients`. Inside, the message asks `Room#applicable_activity_types(message)` and runs each channel for each applicable type. Substance lives on the model.

**Why one job per message:** a single message that is both `:mention` and `:everyone_room_message` would otherwise enqueue two jobs, each loading the same message, room, and memberships. The activity-type vocabulary stays an internal organizing principle inside `notify_recipients`, not a job-interface argument.

**Boost dispatch is the one exception** — boost is triggered after a `Boost` is created, not after a `Message`. Boost still uses `Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)` to dispatch the single type with a non-creator actor. This is the only call site that uses `only:`.

**`Message` after-commit callback ordering matters.** `Message` already has eight `after_create_commit` callbacks (see `app/models/message.rb`). The new dispatch callback must fire **after** `create_mention_notifications` and `update_thread_reply_count`, because the dispatcher reads mention notifications and thread-count state. Document the order explicitly when adding the callback; do not rely on declaration order being load-bearing — make it explicit via callback name + optional `if:` checks.

**Recipient sets are channel-specific.** Row recipients can be broader than push recipients (e.g. `@everyone` creates rows for all room members but pushes only to `involved_in_mentions ∩ involved_in_everything`-disjoint sets). Email recipients follow the row set, then narrow via the email gate.

### 5.1 Push delivery details

`Room::MessagePusher` survives, but its scope narrows. Today (`app/models/room/message_pusher.rb`) it does both routing (`push_to_users_involved_in_everything` / `push_to_users_involved_in_mentions`) and payload formatting (`build_payload` with the two-branch `room.direct?` shape). After this change:

- **Recipient resolution moves up to `Message`.** `Message#push_recipient_user_ids_for(activity_type)` returns the candidate user-id set per activity type. `Membership::Notifiable#receives_push_for?` filters those candidates per recipient. The `Membership.involved_in_everything` / `Membership.involved_in_mentions` scopes still drive the disjoint subsets but are now invoked from `Message`, not `Room::MessagePusher`.
- **Payload formatting stays in `Room::MessagePusher#build_payload`.** The two-branch `room.direct?` shape is preserved verbatim — same direct/shared push copy as today. `Message#deliver_push_for(activity_type)` builds the payload via `Room::MessagePusher.new(room:, message:).build_payload` (or a class-method wrapper) and queues delivery through the existing `Rails.configuration.x.web_push_pool`.
- **No `Notification::PushTarget` plugin hierarchy in v1.** Fizzy's shape (`Notification::PushTarget::Web`, with extension points for APNs / FCM) is the right pattern when a second delivery target lands. Until then, single-target delivery via `web_push_pool` stays inline.
- **No `Notification::*Payload` class hierarchy in v1.** Push copy does not diverge per activity type today — only by `room.direct?`. When copy *does* diverge per type (e.g. boost push gets a distinct shape, or mention push wants a different title than DM push), mirror Fizzy's `Notification::DefaultPayload` / `EventPayload` / `MentionPayload` shape. Defer until the divergence is real.

**Why push is not driven by `Notification.after_save_commit` (Fizzy's pattern):** two of Sabha's five dispatcher activity types (`:direct_message`, `:everyone_room_message`) never produce `Notification` rows, so a Notification-driven push trigger would lose those channels entirely. Sabha's push driver must sit at the `Message` level. Fizzy's `Notification::Pushable` concern (`fizzy/app/models/notification/pushable.rb`) is the prior art for the *target* hierarchy and *payload* hierarchy when v1.1 needs them — it is not the right shape for the dispatch trigger.

## 6. Data models

### 6.1 `User::NotificationSettings` (new, tenanted)

| Column | Type | Notes |
|---|---|---|
| `user_id` | references, unique | One row per user. Built on user creation. |
| `mode` | string enum | `nothing` / `mentions_and_dms` (default) / `all`. Default involvement for new memberships + soft suppressor for outbound channels. |
| `missed_email_enabled` | boolean, default `false` | Master switch for missed-notification email. |
| `email_frequency` | string enum, default `hourly` | `hourly` / `daily`. Bundle window length. |
| `weekly_digest_subscribed` | boolean, default `true` | Member-level digest opt-out. Defaults to subscribed so an admin enabling the digest reaches existing members immediately (PRD § Product principles #6: weekly general activity is "a workspace/admin choice with member opt-out"). Independent of `missed_email_enabled`. Aggregate exposure is gated by `account.weekly_digest_enabled` (default `false`). |
| `push_enabled` | boolean, default `true` | Master switch for WebPush. |
| `last_digest_sent_at` | datetime, nullable | Dedup guard for the weekly digest job. |

### 6.2 `Notification::Bundle` (new, tenanted)

A per-user time window that accumulates eligible missed-notification candidates. Inspired by Fizzy's `Notification::Bundle`.

| Column | Type | Notes |
|---|---|---|
| `user_id` | references | Owner. |
| `frequency` | string enum | Snapshot of `email_frequency` at bundle creation. Decouples in-flight bundles from later preference changes. |
| `starts_at` | datetime | Window open time. |
| `ends_at` | datetime | Scheduled delivery time. `BundleDeliveryJob` is scheduled with `wait_until: ends_at` at bundle creation. |
| `delivered_at` | datetime, nullable | Set when the email is sent. |
| `canceled_at` | datetime, nullable | Set when the bundle is canceled (user returned, all items dropped, etc.). |

Indexes:

- `(user_id, ends_at)` — lookup of the active bundle for a user.
- **Partial unique index** `(user_id) WHERE delivered_at IS NULL AND canceled_at IS NULL` — makes "at most one active bundle per user" a database invariant, not an application invariant. Two simultaneous Message creates for the same user (DM + mention in the same second) cannot race-create two active bundles; the second insert raises `ActiveRecord::RecordNotUnique`, which the find-or-create path retries by reading the now-existing row.

Active bundle for user `u` = the row with `user_id = u`, `delivered_at IS NULL`, `canceled_at IS NULL`, `ends_at > now()`. There is at most one active bundle per user at a time, enforced by the partial unique index above.

### 6.3 `Notification::BundleItem` (new, tenanted)

| Column | Type | Notes |
|---|---|---|
| `bundle_id` | references | The bundle this item belongs to. |
| `message_id` | references | The message that triggered the candidate. |
| `actor_id` | references (user) | The sender. |
| `kind` | string | `mention` / `direct_message`. Email-routing reason for this item. |
| `created_at` | datetime | When the item was added. |

Unique index: `(bundle_id, message_id, kind)` — a single message can produce a `:mention` and a `:direct_message` row in different rooms but never the same pair twice in one bundle.

**Why `kind` instead of `activity_type`:** the column is **not** the same vocabulary as `Notification.activity_type`. Bundle items include `:direct_message` (which never produces a `Notification` row); `Notification.activity_type` does not. Sharing the column name across two non-equal vocabularies would breed bugs ("why is there no Notification with `activity_type = 'direct_message'`?"). A different column name makes the split honest.

**Why a separate item table instead of attaching `Notification` rows to bundles:** `:direct_message` does not create `Notification` rows in v1, and we don't want bundling to force a UX change to the Activity tab. Bundle items are an email-only concern and stay isolated.

### 6.4 Existing tables — touched columns

| Table | Change |
|---|---|
| `accounts` | Add `email_notifications_enabled` (bool, default `false`) and `weekly_digest_enabled` (bool, default `false`). Both are admin-controlled. |
| `notifications` | No schema change. Vocabulary stays `%w[mention boost thread_reply]`. |
| `memberships` | No new columns. |
| `users.preferences` | Existing JSON column. **Used by the Slack importer for import-provenance metadata** (`slack_import`, `slack_user_id`, `system_user` keys; queried via `json_extract` at `lib/slack/users_importer.rb:31`). Notification settings get a separate table because (a) they are orthogonal to Slack-import lineage, (b) `last_digest_sent_at` and `email_frequency` benefit from real indexed columns and Rails enum affordances (bang methods, predicates, query scopes), (c) `store_accessor` over JSON loses those affordances. Do not extend `preferences` for notification state. |

## 7. Section A — Missed-notification email subsystem

### 7.1 Pipeline

```
Eligible (message, activity_type, recipient)
        │
        ▼
Find-or-create active bundle for recipient
        │
        ▼
Insert NotificationBundleItem (bundle_id, message_id, kind, actor_id)
        │
        │  (time passes; bundle window = 1h or 24h based on frequency)
        ▼
Bundle ends_at fires → Notification::BundleDeliveryJob(bundle)
        │
        ▼
Re-evaluate each item via Membership::Notifiable predicates
        │
        ├─ all items dropped → cancel bundle, no email
        └─ items remain    → render and deliver MissedNotificationsMailer.bundle(user, items)
                              set bundle.delivered_at
```

### 7.2 Find-or-create active bundle

At dispatch time, `Notification::Bundle.find_or_create_active_for(user)` returns the bundle with `ends_at` in the future. If none exists, create one with `frequency` snapshotted from `user.notification_settings.email_frequency` and `ends_at = starts_at + frequency_window`.

`frequency_window`:

- `hourly` → 1 hour.
- `daily` → 24 hours.

This is computed once at bundle creation and never moves. A user who switches from hourly to daily mid-window keeps the current bundle on its original schedule; the next bundle uses the new frequency.

### 7.3 Send-time revalidation

`BundleDeliveryJob` walks `bundle.items` and asks `membership.receives_missed_email_for?(item.message, item.kind)` for each. Items where the predicate returns false are dropped (membership revoked, message deleted, room destroyed, sender blocked, user no longer away, account flag flipped, `missed_email_enabled` disabled). If all items drop, the job marks the bundle `canceled_at` and exits.

If the user has an active connection in the workspace at delivery time, the entire bundle is canceled — they are no longer "away."

### 7.4 Cancellation triggers (no explicit job cancellation needed)

- User reconnects to the workspace → next delivery sees `workspace_locally_away?` false → bundle canceled.
- User flips `missed_email_enabled` off → delivery re-checks per item → all items drop.
- Account flag flipped off → delivery re-checks → all items drop.
- Sender blocks recipient (or vice versa) → delivery re-checks → blocked items drop.

The delivery job is the single revalidation point. No active job cancellation, no per-item bookkeeping.

### 7.5 Cooldown

Bundle window is the cooldown. There is no separate per-membership cooldown. A second mention 30 seconds after the first lands in the same bundle and produces a single email at delivery time.

### 7.6 Bundle garbage collection

Delivered or canceled bundles are pruned **inside the existing weekly digest job's per-workspace loop** (see § 8.1) — no separate cron entry. At the top of each per-workspace digest run, before iterating subscribed members, the job runs:

```ruby
Notification::Bundle.where("delivered_at IS NOT NULL OR canceled_at IS NOT NULL")
                    .where("updated_at < ?", 90.days.ago)
                    .delete_all
```

`Notification::BundleItem belongs_to :bundle, dependent: :delete_all` cascades the items. 90 days is chosen because it covers any reasonable support-investigation horizon ("why did I not get an email three months ago") without leaving terminated bundles around indefinitely.

Active bundles (`delivered_at IS NULL AND canceled_at IS NULL`) are never pruned by this job. A user who stays away forever continues to accumulate active bundles at the bundle-window cadence; that is acceptable because the active set per user is bounded (one at a time, due to the partial unique index in § 6.2).

Folding GC into the weekly digest loop avoids introducing a second per-workspace cron concept. If the weekly digest job is later disabled or reshaped, GC needs to find a new home — note this in any future digest-removal proposal.

### 7.7 Idempotent delivery on retry

`BundleDeliveryJob` is retryable by Solid Queue on transient failure (5xx provider errors, network timeouts, rate limits). A naive deliver-then-set-`delivered_at` shape has a race window: if the mailer call succeeds but the subsequent `delivered_at` write fails, the next retry would re-send. The doc commits to one safeguard:

**Provider-side idempotency key, stable per bundle.** Every send passes `idempotency_key: "bundle-#{bundle.id}"` (or equivalent provider-specific parameter):

- **Resend** — `idempotency_key:` parameter on `Resend::Emails.send`. Resend deduplicates server-side for 24 hours; second call returns the same `id` without re-sending.
- **SES** — `MessageDeduplicationId` (FIFO-style dedup) via the SES Configuration Set, OR client-side `idempotency_key` via the v2 SDK if available. Provider deduplicates within the configuration's dedup window.

After a successful API response, `bundle.delivered_at` is set. If the DB write then fails, Solid Queue retries the job; the retry's `deliver_now` call hits provider-side dedup and is a no-op for sending purposes; the retry then sets `delivered_at` again (idempotent at the DB level too — same value, same row).

**Why provider-side dedup over a "claim before deliver" pattern.** An atomic-claim shape (`UPDATE bundles SET delivered_at = NOW() WHERE id = ? AND delivered_at IS NULL`) has the inverse failure mode: claim succeeds, delivery then fails transiently → retry sees `delivered_at` set → email is permanently lost. The provider-side dedup fails open (always sends if provider hasn't seen the key yet) rather than failing closed.

**Idempotency key format must be stable across retries.** `bundle-#{bundle.id}` is enough — `bundle.id` doesn't change between retries, and the bundle is a singleton per user-window so there's no collision risk across users. Do **not** include `Time.current` or any per-attempt value in the key.

v1 does not have a per-membership cooldown column because bundling already coalesces. Provider idempotency is a separate concern about retry safety inside one bundle's delivery.

### 7.8 Mailer

`MissedNotificationsMailer#bundle(user, items)`:

- Subject: generic, no sender/room name. e.g. `"New mentions in {Workspace}"` or `"You have new messages in {Workspace}"`.
- Body: groups items by room, lists sender names + truncated previews per item, primary CTA to Activity, secondary link to settings, unsubscribe link.
- Sets RFC 8058 `List-Unsubscribe` and `List-Unsubscribe-Post` headers.
- Token mints via `Rails.application.message_verifier(:email_unsubscribe)` with `{ user_id, tenant, surface: :missed_notifications }`.
- Passes `idempotency_key: "bundle-#{bundle.id}"` on the underlying provider API call (see § 7.7).

`surface:` field scopes the unsubscribe to this email surface — clicking unsubscribe in a missed-notification email does not unsubscribe from the weekly digest, and vice versa (PRD § Settings).

## 8. Section B — Weekly activity digest subsystem

### 8.1 Pipeline

```
Notification::WeeklyDigestJob (cron, weekly per workspace)
        │
        ▼
Account.weekly_digest_enabled? ──no──▶ exit
        │ yes
        ▼
For each user where:
  - notification_settings.weekly_digest_subscribed
  - user is verified, active, not banned, not deactivated, not bot
  - user has not received a digest in the last 6 days (last_digest_sent_at)
        │
        ▼
Generate digest content from accessible recent activity (see 8.3)
        │
        ├─ no qualifying content → skip user, do not send empty digest
        └─ content available     → WeeklyDigestMailer.digest(user, content)
                                    set last_digest_sent_at
```

### 8.2 No persistent bundle

The digest is generated per send, not accumulated like missed-notification bundles. Content selection runs at send time against the live tenanted DB; failures and skips do not need rollback.

`last_digest_sent_at` on `user_notification_settings` is the dedup guard. A re-run of the job within 6 days skips users who already received their weekly send.

### 8.3 Content selection (rules, not algorithm)

Content for a member is drawn from rooms the member can access (active membership, not `:invisible`, not `:nothing`):

1. **Notification-worthy first:** room-wide `@everyone` mentions in the past week that the member would have received an in-app row for, but did not view.
2. **Recently active rooms:** rooms with N+ messages in the past week that the member is a non-DM member of.
3. **Excerpts:** small number of public/shared discussion excerpts. No DM content. No private rooms the member cannot access.

The job stays conservative — no algorithmic ranking, no Discord-style Highlights (PRD § Competitive reference takeaway). If a member's accessible rooms are quiet, the digest is skipped, not padded.

### 8.4 Mailer

`WeeklyDigestMailer#digest(user, content)`:

- Subject: workspace-recap framing, not a personal alert. e.g. `"This week in {Workspace}"`.
- Body: workspace name, recap section, recent excerpts, CTA to Activity, manage settings, unsubscribe.
- Token surface: `:weekly_digest`. Independent unsubscribe scope.

## 9. Multi-tenant boundaries

| Lives on | Storage | Effect |
|---|---|---|
| `User::NotificationSettings` (mode, frequency, both opt-ins, push toggle) | Tenanted DB | Per-workspace. A user in workspaces A and B has independent settings in each. |
| `Notification::Bundle` + `BundleItem` | Tenanted DB | Bundles are per-workspace. Cross-workspace consolidation is out of scope. |
| `Account.email_notifications_enabled` / `weekly_digest_enabled` | Tenanted DB (single-row Account) | Per-workspace admin toggles. |
| `Push::Subscription` | Tenanted DB | Existing — already per-workspace. |
| `last_digest_sent_at` | Tenanted DB | Per-workspace dedup. A user gets one digest per workspace per week. |
| Email address | Untenanted (`GlobalIdentity` in SaaS) | One outbound address regardless of which workspace fired the email. Subject/From line carries the workspace name. |

**Unsubscribe tokens** carry `{ user_id, tenant, surface }`. The unsubscribe controller decodes the token, enters the encoded tenant via `ApplicationRecord.with_tenant(...)`, then flips the appropriate column based on `surface`. A click from workspace A's missed-notification email does not affect workspace B or A's digest subscription.

**Self-hosted (single-tenant)** collapses to "global per user" — `tenant: nil` on the token, `with_tenant` is a no-op.

## 10. Global mode and per-channel switch interactions

| State | Push | Missed-notification email | Weekly digest | In-app rows |
|---|---|---|---|---|
| `mode: nothing` (and not `:everything` per-room) | suppressed | suppressed | unaffected (digest is opt-in separately) | created |
| `mode: nothing` and `involvement: everything` for a room | fires (per-room override) | fires | unaffected | created |
| `missed_email_enabled: false` | unaffected | suppressed | unaffected | created |
| `weekly_digest_subscribed: false` | unaffected | unaffected | suppressed | created |
| `push_enabled: false` | suppressed | unaffected | unaffected | created |

Two-layer reconciliation between global `mode` and per-room `involvement`:

- `Membership#effective_involvement` (see § 4) is the **delivery-time source of truth** per room. It folds the two-source rule into one method so call sites never check `mode` and `involvement` independently.
- Global `mode` is the **default for new memberships**. At delivery time, its only effect on outbound channels is via `effective_involvement` (which returns `"nothing"` when `mode: "nothing"` and the membership is not `:everything`).

In-app rows are created regardless of `mode` — the Activity tab is the truth-on-return surface.

## 11. Mailers and unsubscribe

Two mailers:

- `MissedNotificationsMailer` — `bundle(user, items)`.
- `WeeklyDigestMailer` — `digest(user, content)`.

Both inherit `ApplicationMailer` directly and `include EmailUnsubscribable` — a small concern (`app/mailers/concerns/email_unsubscribable.rb`) that provides:

- Token minting (`message_verifier(:email_unsubscribe)`, surface-scoped).
- RFC 8058 unsubscribe headers (`List-Unsubscribe`, `List-Unsubscribe-Post`).
- Workspace name resolution from `Account.sole.name` (runs inside the resolved tenant).

A `NotificationMailer` base class layer is **not** introduced for two subclasses. Two mailers don't earn a base — extract one if a third surface arrives.

### 11.1 Delivery wiring

Email delivery uses provider-specific gems wired through standard `ActionMailer::Base.delivery_method` config — already configured in this repo. Split by deployment mode:

| Mode | Provider | Gem | Notes |
|---|---|---|---|
| **SaaS** | Amazon SES | `aws-sdk-rails` | AWS-native; Sabha SaaS already runs on AWS infrastructure. Higher throughput ceiling once production access is granted. |
| **Self-hosted** | Resend | `resend-rails` | Friendlier onboarding for self-hosters who don't want AWS complexity. Self-hosted operators verify their own domain in Resend. |

**SaaS sender domain is shared** across all workspaces — single verified domain (e.g. `notifications@<sabha-domain>`). The workspace name appears in the `From` display and `Subject` (`"[#{Account.sole.name}] "` prefix), not in the domain. Per-workspace BYO sending domains are deferred to v1.1.

**Self-hosted operators must verify a sending domain in Resend** before email turns on. This is encoded by the account-level `email_notifications_enabled` flag staying `false` until DNS is configured. The setup itself (DKIM/SPF/DMARC records, Resend domain verification) is operator-side, documented separately from this architecture doc.

**No provider abstraction in v1.** The doc names each provider directly. A `Notification::EmailProvider` interface that abstracts SES vs Resend would be premature — both providers already conform to the ActionMailer delivery_method API, so the abstraction is built into Rails. If a third provider arrives, then revisit.

**Two operator-level gates above the per-workspace toggles** keep the dormant-by-default rollout honest and give the platform an emergency stop:

| Gate | Lives in | Returns false when… | Consequence |
|---|---|---|---|
| `Sabha.email_configured?` | `lib/sabha.rb` | Self-hosted production with no provider creds (no `RESEND_API_KEY`, or `EMAIL_PROVIDER=ses` without `aws-sdk-sesv2`); or `EMAIL_GLOBALLY_DISABLED=true` regardless of mode | Admin email section hidden; dispatch and digest job no-op |
| `account.email_notifications_enabled?` / `weekly_digest_enabled?` | DB (tenanted) | Per-workspace admin hasn't flipped them on | Per-workspace opt-in still applies |

`EMAIL_GLOBALLY_DISABLED=true` is the SaaS-side **kill switch**: a single env-var flip + restart halts all outbound notification mail across every tenant without touching any per-workspace state, so flipping it back off restores each workspace's prior preference. The gate is consulted at three sites (the admin partial, `Membership::Notifiable#account_email_notifications_enabled?`, and `Notification::WeeklyDigestJob`) so a stale `true` value in the DB can't trigger sends once the kill switch is armed. Documented in `docs/multi-tenant/DEPLOYMENT.md`.

### 11.2 Bounce, complaint, and suppression handling — deferred to v1.1

v1 ships **without** webhook-driven bounce/complaint suppression and **without** any SMTP-failure-rescue fallback. There is no `EmailDeliveryObserver`. Hard-bouncing addresses continue to receive mail until v1.1.

This is acceptable because:

- **The account-level `email_notifications_enabled` flag defaults off**, gating exposure during rollout. Email volume during the v1 window is bounded to consenting workspaces.
- **Both providers (SES and Resend) maintain their own provider-side suppression lists.** Persistent hard bounces eventually hit those lists and the providers stop accepting messages to those addresses on our behalf. Sabha won't see worsening sender reputation as fast as it would with raw SMTP.
- **v1.1 will land webhook ingestion** (`Webhooks::SesController` for SaaS via SNS, `Webhooks::ResendController` for self-hosted) with signature verification, bounce/complaint event parsing, and a `missed_email_enabled: false` flip on permanent bounces. Webhook-driven, not in-process exception handling.

**Why no SMTP-rescue stopgap.** API-based delivery doesn't raise `Net::SMTPFatalError`; it raises provider-specific errors (`Aws::SES::Errors::*`, `Resend::Error`) that don't reliably map to "permanent failure" the way 5xx SMTP responses do. Building a stopgap mapping for two providers in v1 is more code than it saves; deferring to webhooks is cleaner. Worst case in the gap window: a small number of bounces sit on user-account preference state until v1.1, mitigated by rollout gating.

Subject privacy (PRD § Email content): generic subjects, no sender or room names. Sender/room names appear in the body.

## 12. User and account defaults summary

- Existing users: `missed_email_enabled: false`, `weekly_digest_subscribed: true`, `mode: mentions_and_dms`, `push_enabled: true`, `email_frequency: hourly`. Digest defaults subscribed because the digest is admin-enabled with member opt-out (PRD § Product principles #6); aggregate exposure is gated by `account.weekly_digest_enabled` defaulting `false`.
- New users: same.
- Account: `email_notifications_enabled: false`, `weekly_digest_enabled: false`. Admins flip both on.

## 13. Out of scope (v1)

- **Thread-reply email.** Deferred to v1.1+. Slack supports it for followed threads. Sabha has the equivalent recipient set today (thread members + parent room `involved_in_everything`, minus already-mentioned users — see `app/jobs/create_thread_reply_notifications_job.rb`), so the addressing is solved; what's deferred is the volume question. A single active thread can produce 20 replies in a window, which would push past the PRD's "calm timing" target. Revisit once v1 bundle-volume telemetry shows headroom; the path is to add `:thread_reply` to `Notification::Routing::EMAIL_TYPES` and `notification_bundle_items.kind`.
- Boost email. Neither Slack nor Discord email reactions; not planned.
- Per-room email controls.
- Keyword alerts / custom triggers. Slack has "My keywords"; Sabha treats this as a v2 product question, not a v1.1 implementation question — keyword alerts are explicitly the *ambient* surface, outside v1's "personal beats ambient" frame.
- Marketing/news email subscriptions (separate surface).
- Reply-from-email.
- Cross-workspace bundle consolidation (a user in 3 workspaces gets up to 3 bundles).
- **Snooze / DND / pause notifications.** Out of scope for v1 entirely (PRD § Confirmed decisions #7). Master switches (`missed_email_enabled`, `push_enabled`) and per-room `Membership#involvement: :nothing` are the v1 ways to silence notifications.
- Bounce / complaint / suppression handling. v1 ships **no** auto-suppression of any kind (no SMTP-rescue, no observer, no webhook ingestion). v1.1 adds webhook-driven suppression via `Webhooks::SesController` (SaaS, fed by SNS) and `Webhooks::ResendController` (self-hosted), both flipping `missed_email_enabled: false` on permanent bounces or complaints. v1's exposure is bounded by the account-level `email_notifications_enabled` flag defaulting off. See § 11.2.
- Personalized digest ranking (Discord Highlights-style). Digest stays a conservative recap.
- Admin-authored digest content. Digest is generated from workspace activity, not curated.
- Per-user timezone digest send time. v1 uses a workspace-default day/time.

## 14. Architectural decisions and open questions

### 14.1 Resolved

- **Email "away" threshold = `:away` tier (1 hour)** *(decided 2026-05-09)*. `workspace_locally_away?` returns true when the user's most recent connection in any of this workspace's memberships is more than `Membership::Connectable::ACTIVITY_TIERS[:away]` (1 hour) ago, or never. The tighter `:active` tier (10 minutes) was rejected because email asks "has the user been gone long enough that an email is the right way to reach them?", not "should we show a green dot?" — a brief mid-window visit means the user could plausibly have seen the message live, so the bundle should drop at delivery time. See § 4 for full rationale.
- **Bundle GC = 90 days, run inside weekly digest job** *(decided 2026-05-09)*. Delivered or canceled bundles older than 90 days are pruned at the top of each per-workspace weekly digest run. Active bundles are never pruned (they're naturally bounded to one per user via the partial unique index in § 6.2). The two-table bundle shape (parent `Notification::Bundle` + child `BundleItem`) was kept over a single-table reshape because the parent earns its keep — `frequency` snapshot decouples in-flight delivery from preference flips, single `delivered_at`/`canceled_at` makes delivery atomic, and `(user_id) WHERE delivered_at IS NULL AND canceled_at IS NULL` is a clean DB invariant. See § 7.6 for the GC mechanics.
- **Weekly digest fires regardless of recipient activity** *(decided 2026-05-09)*. A subscribed member who was active every day this week still receives the digest. The only gates are `weekly_digest_subscribed: true`, account-level `weekly_digest_enabled: true`, basic user health (verified/active/not-banned/not-bot), and 6-day dedup via `last_digest_sent_at`. The PRD's stated purpose ("bring less-active members back") suggests presence-aware sending, but a presence gate was rejected for v1: it adds a new threshold (`DIGEST_INACTIVE_WINDOW`), creates subscriber confusion ("I subscribed but didn't get one"), and weakens the simple opt-in mental model. Active members who find the digest noisy can unsubscribe; the unsubscribe scope is digest-specific (§ 11). Revisit in v1.1 if subscribed-active-member complaints surface.
- **Email provider split: SES for SaaS, Resend for self-hosted** *(decided 2026-05-09)*. SaaS uses Amazon SES via `aws-sdk-rails` (AWS-native, matches deployment infra); self-hosted uses Resend via `resend-rails` (operator-friendly, no AWS prerequisite). Both providers conform to the standard ActionMailer `delivery_method` API, so no provider-abstraction layer is needed in v1. SaaS sender domain is shared across all workspaces; per-workspace BYO sending domain is deferred to v1.1. See § 11.1.
- **No bounce/complaint suppression in v1; webhooks land in v1.1** *(decided 2026-05-09)*. v1 ships without any auto-suppression — no SMTP-rescue fallback, no observer, no webhook ingestion. API-based delivery (SES, Resend) doesn't raise SMTP errors, so there's no exception path to rescue. v1's bounce-exposure risk is bounded by the account-level `email_notifications_enabled` flag defaulting off. v1.1 adds `Webhooks::SesController` (SaaS via SNS) and `Webhooks::ResendController` (self-hosted) for webhook-driven suppression. See § 11.2.
- **Empty digest skip does not update `last_digest_sent_at`** *(decided 2026-05-09)*. When `WeeklyDigestJob` finds no qualifying content for a member (per § 8.3 selection rules) and skips them, the dedup column is **not** touched. `last_digest_sent_at` means "last actual delivery," not "last attempt." Pros: cleaner semantics for support/debugging ("did we ever email this user?" answers correctly), and the member is re-evaluated next week instead of being dedup-locked through a quiet stretch. Cons: a member in a perpetually quiet workspace gets re-evaluated every week with no work done — but the work is bounded (single content-selection query per member, exits in milliseconds when no content qualifies). The empty-bundle case stays as written: bundles with no surviving items at delivery time are marked `canceled_at`, distinct from skips.
- **Stuck bundles on terminal delivery failure are marked `canceled_at` in v1** *(decided 2026-05-09)*. `BundleDeliveryJob` rescues documented terminal provider errors (e.g. `Aws::SES::Errors::MessageRejected`, `Aws::SES::Errors::MailFromDomainNotVerified` for SES; 4xx-except-429 for Resend) and sets `bundle.canceled_at`, breaking the partial-unique-index "still active" trap that would otherwise prevent the user's next bundle from being created. Transient errors (5xx, timeouts, rate limits) propagate so Solid Queue retries the job per its standard policy. This is not the same as v1.1 webhook-driven suppression: it terminates the bundle so the system can keep working, but does **not** flip `missed_email_enabled` — that's a per-user preference change that needs the richer event data webhooks provide. The rescue list lives next to `BundleDeliveryJob` and is short (each provider's terminal error class names); if a new provider arrives the list grows.

### 14.2 Open

- **Bundle frequency change mid-window.** Decision: in-flight bundles keep their original `frequency`; next bundle uses new pref. Confirm this matches PRD intent before plan.
- **Digest send day/time.** Workspace-default needs a concrete value (e.g. Mondays 09:00 in workspace TZ if known, else UTC). PRD defers to product default. Pick before plan.
- **Bundle item index vs query cost.** `(bundle_id, message_id, kind)` unique index handles dedup. At delivery time the join `bundle_items × messages × memberships` could be large for very chatty workspaces. Plan needs to confirm query shape stays under acceptable bound.
- **`@everyone` digest weighting.** PRD says notification-worthy activity comes first in digest. Define "notification-worthy" precisely — `@everyone` mentions only, or `@everyone` + named mentions the user missed?
- **Backfill behavior on deploy.** Existing `User` rows need `user_notification_settings` with safe defaults. `User.where.missing(:notification_settings).find_each(&:create_notification_settings!)` is idempotent; confirm in plan.

## 15. Glossary

- **Activity type** — symbol describing what happened to a message (`:mention`, `:direct_message`, etc.). Routing input.
- **Channel** — output target for a notification: in-app row, push, missed-notification email, weekly digest.
- **Bundle** — per-user time window that accumulates missed-notification email candidates.
- **Send-time revalidation** — re-running eligibility predicates at delivery time so state changes during the window cancel correctly.
- **Workspace-locally away** — user has no connection in *this* workspace's memberships in the last hour (`Membership::Connectable::ACTIVITY_TIERS[:away]`). Does not consider activity in other workspaces.
- **Surface** — distinct email product (missed-notification vs weekly digest). Each surface has its own opt-out and its own unsubscribe token scope.

## Appendix A. V0 → v1 deltas

The previous notification plan (`UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md`, superseded 2026-05-09) proposed a per-event delayed-email shape with several columns, methods, and patterns that v1 does not adopt. This appendix is the consolidated "what V0 had that v1 doesn't" so anyone arriving from V0 can find the deltas in one place rather than reading them inline across the doc.

### A.1 Columns dropped

| V0 column | Why dropped |
|---|---|
| `memberships.last_email_notified_at` | V0's per-membership cooldown anchor for the 5-minute "don't email twice from the same room within 5 min" rule. Bundling supersedes it — the bundle window is the cooldown, and it operates per-user instead of per-membership (strictly better: no more N emails for N rooms in 5 minutes). |
| `user_notification_settings.email_when_away` | Renamed to `missed_email_enabled` — column name shouldn't encode the "when away" policy, which is the dispatcher's question. |
| `user_notification_settings.snooze_until` and `snooze_indefinite` | Snooze is out of scope per `EMAIL-NOTIFICATIONS-PRD.md` § Confirmed decisions #7. |

### A.2 Methods and constants dropped

| V0 method/constant | Why dropped |
|---|---|
| `Membership#claim_email_cooldown!` (atomic conditional UPDATE) | Bundling makes per-membership cooldown unnecessary. |
| `Membership::EMAIL_COOLDOWN = 5.minutes` | Same reason. |
| `Notification::EmailJob::EMAIL_GRACE_WINDOW = 5.minutes` | Replaced by per-user `email_frequency` (`hourly` / `daily`) for the bundle window. |
| `User#email_mention_notification`, `User#email_direct_message_notification` per-event verbs | Replaced by `MissedNotificationsMailer#bundle(user, items)` — one delivery per window covers all kinds. |

### A.3 Components dropped or replaced

| V0 component | v1 replacement |
|---|---|
| `Notification::EmailJob` (per-event delayed email scheduled with `wait: 5.minutes`) | `Notification::BundleDeliveryJob` (per-bundle delivery scheduled with `wait_until: bundle.ends_at`) |
| `EmailDeliveryObserver` SMTP-failure auto-suppress | Not in v1; v1.1 replaces with webhook ingestion (`Webhooks::SesController`, `Webhooks::ResendController`) |
| `Net::SMTPFatalError` / `Net::SMTPSyntaxError` rescue path | Not relevant to API-based delivery (SES, Resend). v1 has no rescue path; v1.1 webhooks handle suppression |
| `Notification::DispatchJob.perform_later(message, activity_type, actor)` (one job per `(message, activity_type)`) | `Notification::DispatchJob.perform_later(message)` (one job per message) — boost is the lone exception via `only: :boost, actor: booster` |

### A.4 Patterns considered and rejected

| Pattern | Why rejected |
|---|---|
| "Claim before deliver" atomic UPDATE on bundles | Fails closed (silent loss on transient delivery failure). Replaced by provider-side idempotency keys (§ 7.7). |
| Single-table `pending_email_notifications` (no parent bundle row) | Parent table earns its keep — `frequency` snapshot, atomic terminal state, partial-unique-index invariant, GC anchor. Recorded in § 14.1. |
| `Membership::Notifiable` carrying routing-vocabulary constants (`EMAIL_TYPES`, `IN_APP_ROW_TYPES`, etc.) | Moved to `Notification::Routing` — Membership is recipient context, not routing vocabulary (§ 3). |
| `NotificationMailer` base class for two subclasses | Two mailers don't earn a base. Concern (`EmailUnsubscribable`) instead (§ 11). |
| `User#generate_token_for(:email_unsubscribe)` for unsubscribe tokens | Cannot carry tenant identity, which SaaS requires. `Rails.application.message_verifier(:email_unsubscribe)` carries `{ user_id, tenant, surface }` (§ 9). |

### A.5 What V0 got right and v1 keeps

To balance the deltas: most of V0's routing and gating shape carried forward. v1 inherits the dispatcher pattern, `Membership::Notifiable` predicates, the per-recipient decision tree, the workspace-local away check, the per-room override / global mode layering rule, the broad row recipient set for `@everyone`, the unsubscribe-via-`message_verifier` shape, and the `discard_on ActiveJob::DeserializationError` job pattern. The deltas are concentrated in email delivery shape (per-event → bundled), suppression handling (in-process rescue → deferred webhook), and a handful of rename / extract refactors from the DHH-style review. The dispatcher and eligibility cores are largely V0.

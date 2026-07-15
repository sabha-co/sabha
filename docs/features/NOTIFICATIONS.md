# Sabha notifications architecture

All notification channels — in-app rows, push, missed-notification email (bundled), weekly activity digest email — flow through one dispatcher. This doc maps the shipped components; it is not a forward plan.

---

## 1. Architectural shape

1. **One dispatcher** decides what fires per recipient per event across all channels.
2. **Missed-notification email is bundled**, not per-event. Hourly or daily windows, user-selectable.
3. **Weekly digest is a separate pipeline** — different copy, cadence, opt-out, gates.
4. **Send-time revalidation** is the cancellation path. State changes during a bundle window (return, block, delete, opt-out) drop items at delivery time.
5. **Tenant-safe by construction.** Per-workspace settings, per-workspace bundles, per-workspace digest. Identity and email address are the only untenanted touchpoints.
6. **Default safe.** Email is gated off at the workspace level. Both email surfaces default off for users.

## 2. Channels

| Channel | Trigger | Storage |
|---|---|---|
| In-app row | Per-message, when activity_type creates a `Notification` row | `notifications` table (existing) |
| Push (WebPush) | Per-message, when membership is push-eligible and the member isn't watching the room (per the AnyCable broker) | `push_subscriptions` (existing) |
| Missed-notification email | Per-message, eligible items accumulate into a per-user bundle and deliver hourly/daily | `notification_bundles` + `notification_bundle_items` (new) |
| Weekly activity digest email | Recurring per-workspace job, generated content for opted-in members | No persistent store; `last_digest_sent_at` per user for dedup |

Channels are independent. A user can be a row recipient and not a push recipient; a bundle item and not a digest recipient.

## 3. Activity types

Dispatcher symbol vocabulary (used at routing time only — does not all map 1:1 to persisted `Notification.activity_type` values):

| `activity_type` | Channels |
|---|---|
| `:mention` (incl. `@everyone`) | in-app row, push, missed-notification email |
| `:direct_message` | push, missed-notification email |
| `:everyone_room_message` | push |
| `:thread_reply` | in-app row, push |
| `:boost` | in-app row |

`:direct_message` and `:everyone_room_message` are dispatcher-only — they never produce `Notification` rows. The persisted `Notification#activity_type` vocabulary stays `%w[mention boost thread_reply]`. The dispatcher's symbol set is a strict superset used only at routing time.

Email is intentionally narrow: `:thread_reply` is currently not emailed (see § 13), `:boost` is not emailed, regular room messages are not emailed. Encoded by `Notification::Routing::EMAIL_TYPES = %i[mention direct_message]`.

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

- **Push:** `user.push_enabled?`, and the member is not currently watching the room. Watching is decided by the dispatcher, not by this predicate — see below.
- **Missed-notification email:** `user.missed_email_enabled?`, account email flag on, `user.workspace_locally_away?`, `activity_type.in?(Notification::Routing::EMAIL_TYPES)`.
- **Weekly digest:** `user.weekly_digest_subscribed?`, account `weekly_digest_enabled?`.

**Two distinct presence checks, from two different sources.**

Push asks anycable-go. It terminates every WebSocket, so its broker already knows who has a room open — `Room::PresenceSet` reads that set over the HTTP API (`GET /api/presence/:stream/users`) and `Message#watching?` subtracts those users from the candidates. One fetch per dispatch job, memoized on the message so every activity type sees the same answer. `receives_push_for?` deliberately says nothing about connectedness: a stale column must not override the live signal.

This replaced a `connected_at` freshness check, which required every open tab to keep the column warm with a timed write — the largest concurrency-scaled write source on the single SQLite writer. The grace period after a socket dies is now anycable-go's `--presence_ttl` (45s, set explicitly), not the old 60-second `CONNECTION_TTL`.

When the broker can't answer, gating falls back to the `connected?` column — coarser and staler, but it only fires when anycable-go is unreachable, which is also when those members are receiving no live messages anyway. Failing open (a redundant push) beats failing closed (a missed one). An **empty** presence set is not a failure: it means nobody is here, and everyone gets pushed.

Email asks the database. `workspace_locally_away?` queries `Membership.last_connected_at_for([id])` against the **`:away` activity tier — 1 hour** — workspace-local, not cross-workspace.

`workspace_locally_away?` returns true when the user's most recent connection in any of this workspace's memberships is more than `Membership::Connectable::ACTIVITY_TIERS[:away]` (1 hour) ago, or never. The `:away` tier is chosen over the tighter `:active` tier (10 minutes) because email is asking a different question than UI presence: not "should we show a green dot" but "has the user been gone long enough that an email is the right way to reach them?" A brief mid-window visit (e.g. user pops in for 2 minutes during an hourly bundle) means the user could plausibly have seen the message live, so the bundle should drop at delivery time. Using the 10-minute tier would email those users; using the 1-hour tier does not.

**Snooze / DND is not supported, in any form.** No `snooze_until` column, no `snooze_indefinite` flag, no presence-as-snooze fallback beyond `workspace_locally_away?`. All "user is unavailable" suppression rides on `workspace_locally_away?` (passive presence) and the per-channel master switches (`missed_email_enabled`, `push_enabled`).

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
       ├──▶ deliver_in_app_row_for(activity_type, actor:)        (in-app row)
       ├──▶ deliver_push_for(activity_type)                      (push)
       └──▶ enqueue_missed_email_candidates_for(activity_type)   (bundle add)

(Weekly digest is independent — see § 8.)
```

**One job per message**, not one job per `(message, activity_type)` pair. `Notification::DispatchJob` is a shallow wrapper that calls `message.notify_recipients`; the message then asks `Room#applicable_activity_types(message)` and runs each channel for each applicable type.

**In-app rows currently flow through legacy callbacks, not the dispatcher.** `deliver_in_app_row_for` is a no-op pass-through — the existing `create_mention_notifications` and `create_thread_reply_notifications` callbacks on `Message` still write the `Notification` rows. The dispatcher branch is wired so a future move of row creation into the dispatcher requires no caller changes. This is intentional: in-app rows are the most-tested path and were not in scope for the dispatcher rewrite.

**Boost is the one call site that passes `only:`.** Boost dispatch fires after a `Boost` is created, not after a `Message`, and calls `Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)` to dispatch the single type with a non-creator actor.

**Recipient sets are channel-specific.** Row recipients can be broader than push recipients (e.g. `@everyone` creates rows for all room members but pushes only to the involvement-eligible subset). Email recipients follow the row set, then narrow via the email gate.

### 5.1 Push delivery details

Push splits cleanly between recipient resolution and payload formatting:

- **Recipient resolution lives on `Message`.** `Message#push_recipient_user_ids_for(activity_type)` returns the candidate user-id set per activity type; `Membership::Notifiable#receives_push_for?` filters those candidates per recipient. The `Membership.involved_in_everything` / `Membership.involved_in_mentions` scopes drive the disjoint subsets and are invoked from `Message`.
- **Payload formatting lives on `Room::MessagePusher`.** `Room::MessagePusher.payload_for(room:, message:)` returns the push payload, with a two-branch `room.direct?` shape (different copy for DMs vs shared rooms). `Message#deliver_push_for` queues delivery through `Rails.configuration.x.web_push_pool`.

The push driver sits at the `Message` level (not on `Notification.after_save_commit`) because two of the five dispatcher activity types — `:direct_message` and `:everyone_room_message` — never produce `Notification` rows. A Notification-driven trigger would lose those channels.

Single-target delivery (browser WebPush) is inline today. If a second delivery target lands (APNs, FCM), the right move is a small `Notification::PushTarget` hierarchy parallel to `Room::MessagePusher`; no such hierarchy exists yet.

## 6. Data models

### 6.1 `User::NotificationSettings` (new, tenanted)

| Column | Type | Notes |
|---|---|---|
| `user_id` | references, unique | One row per user. Built on user creation. |
| `mode` | string enum | `nothing` / `mentions_and_dms` (default) / `all`. Default involvement for new memberships + soft suppressor for outbound channels. |
| `missed_email_enabled` | boolean, default `false` | Master switch for missed-notification email. |
| `email_frequency` | string enum, default `hourly` | `hourly` / `daily`. Bundle window length. |
| `weekly_digest_subscribed` | boolean, default `true` | Member-level digest opt-out. Defaults to subscribed so an admin enabling the digest reaches existing members immediately. Independent of `missed_email_enabled`. Aggregate exposure is gated by `account.weekly_digest_enabled` (default `false`). |
| `push_enabled` | boolean, default `true` | Master switch for WebPush. |
| `last_digest_sent_at` | datetime, nullable | Dedup guard for the weekly digest job. |

### 6.2 `Notification::Bundle` (new, tenanted)

A per-user time window that accumulates eligible missed-notification candidates.

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

**Why a separate item table instead of attaching `Notification` rows to bundles:** `:direct_message` does not create `Notification` rows, and bundling shouldn't force a UX change to the Activity tab. Bundle items are an email-only concern and stay isolated.

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

Delivered or canceled bundles are pruned by `Notification::Bundle.gc_terminal!`, called at the top of `Notification::WeeklyDigestJob#perform` once per per-tenant digest run. The class method prunes:

```ruby
where("delivered_at IS NOT NULL OR canceled_at IS NOT NULL")
  .where("updated_at < ?", Notification::Bundle::GC_RETENTION.ago)  # 90 days
  .delete_all
```

`Notification::BundleItem belongs_to :bundle, dependent: :delete_all` cascades the items. The 90-day retention covers any reasonable support-investigation horizon ("why did I not get an email three months ago") without leaving terminated bundles around indefinitely.

Active bundles (`delivered_at IS NULL AND canceled_at IS NULL`) are never pruned. A user who stays away forever continues to accumulate active bundles at the bundle-window cadence; that is acceptable because the active set per user is bounded to one at a time (partial unique index, § 6.2).

GC piggybacks on the weekly digest's per-tenant cadence rather than introducing a second per-workspace cron concept. If the digest job is ever disabled, GC needs to find a new home.

### 7.7 Idempotent delivery on retry

`BundleDeliveryJob` is retryable by Solid Queue on transient failure (5xx provider errors, network timeouts, rate limits). A naive deliver-then-set-`delivered_at` shape has a race window: if the mailer call succeeds but the subsequent `delivered_at` write fails, the next retry would re-send.

**Mitigation: a stable per-bundle idempotency key on the outbound mail.** `MissedNotificationsMailer#bundle` sets a header:

```ruby
headers["X-Idempotency-Key"] = "bundle-#{bundle.id}"
```

- **Resend** treats `X-Idempotency-Key` as its idempotency mechanism and dedups duplicate sends server-side for 24 hours. A retry after a worker crash hits Resend's cache and is a no-op for sending purposes; Sabha then sets `delivered_at` again (idempotent at the DB level too — same value, same row).
- **SES** has no equivalent per-call idempotency parameter. A worker crash between SES accepting the message and Sabha writing `delivered_at` can cause one duplicate send under SES. The accepted tradeoff is that SES users see at most one extra delivery on a rare retry path; the alternative (atomic "claim before deliver") would risk permanent silent loss on transient failure.

**Idempotency key format is stable across retries.** `bundle-#{bundle.id}` is enough — `bundle.id` doesn't change between retries, and the bundle is a singleton per user-window so there's no collision risk across users. Per-attempt values (`Time.current`, retry count) must never be included.

Bundling itself supersedes the older per-membership 5-minute email cooldown; the bundle window *is* the cooldown.

### 7.8 Mailer

`MissedNotificationsMailer#bundle(user, items)`:

- Subject: generic, no sender/room name. e.g. `"New mentions in {Workspace}"` or `"You have new messages in {Workspace}"`.
- Body: groups items by room, lists sender names + truncated previews per item, primary CTA to Activity, secondary link to settings, unsubscribe link.
- Sets RFC 8058 `List-Unsubscribe` and `List-Unsubscribe-Post` headers.
- Token mints via `Rails.application.message_verifier(:email_unsubscribe)` with `{ user_id, tenant, surface: :missed_notifications }`.
- Passes `idempotency_key: "bundle-#{bundle.id}"` on the underlying provider API call (see § 7.7).

`surface:` field scopes the unsubscribe to this email surface — clicking unsubscribe in a missed-notification email does not unsubscribe from the weekly digest, and vice versa.

## 8. Section B — Weekly activity digest subsystem

### 8.1 Pipeline

```
Notification::WeeklyDigestRunnerJob   (cron entry point, untenanted queue DB)
        │
        ▼  SaaS: ApplicationRecord.with_each_tenant { Notification::WeeklyDigestJob.perform_later }
        ▼  Self-hosted: Notification::WeeklyDigestJob.perform_later
Notification::WeeklyDigestJob          (per-tenant)
        │
        ▼  Notification::Bundle.gc_terminal!  (§ 7.6)
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

The job stays conservative — no algorithmic ranking, no Discord-style Highlights. If a member's accessible rooms are quiet, the digest is skipped, not padded.

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

**SaaS sender domain is shared** across all workspaces — single verified domain (e.g. `notifications@<sabha-domain>`). The workspace name appears in the `From` display and `Subject` (`"[#{Account.sole.name}] "` prefix), not in the domain. Per-workspace BYO sending domains are not currently supported.

**Self-hosted operators must verify a sending domain in Resend** before email turns on. This is encoded by the account-level `email_notifications_enabled` flag staying `false` until DNS is configured. The setup itself (DKIM/SPF/DMARC records, Resend domain verification) is operator-side, documented separately from this architecture doc.

**No provider abstraction.** Each provider is named directly; both conform to the standard ActionMailer `delivery_method` API. A `Notification::EmailProvider` interface that abstracts SES vs Resend would be premature — the abstraction is already built into Rails.

**Two operator-level gates above the per-workspace toggles** keep the dormant-by-default rollout honest and give the platform an emergency stop:

| Gate | Lives in | Returns false when… | Consequence |
|---|---|---|---|
| `Sabha.email_configured?` | `lib/sabha.rb` | Self-hosted production with no provider creds (no `RESEND_API_KEY`, or `EMAIL_PROVIDER=ses` without `aws-sdk-sesv2`); or `EMAIL_GLOBALLY_DISABLED=true` regardless of mode | Admin email section hidden; dispatch and digest job no-op |
| `account.email_notifications_enabled?` / `weekly_digest_enabled?` | DB (tenanted) | Per-workspace admin hasn't flipped them on | Per-workspace opt-in still applies |

`EMAIL_GLOBALLY_DISABLED=true` is the SaaS-side **kill switch**: a single env-var flip + restart halts all outbound notification mail across every tenant without touching any per-workspace state, so flipping it back off restores each workspace's prior preference. The gate is consulted at three sites (the admin partial, `Membership::Notifiable#account_email_notifications_enabled?`, and `Notification::WeeklyDigestJob`) so a stale `true` value in the DB can't trigger sends once the kill switch is armed. Documented in `docs/multi-tenant/DEPLOYMENT.md`.

### 11.2 Bounce and complaint handling (not currently implemented)

Sabha does not currently auto-suppress hard-bouncing or complaining addresses. There is no `EmailDeliveryObserver`, no webhook ingestion, no SMTP-rescue fallback. Exposure is bounded by `account.email_notifications_enabled` defaulting off and by both providers (SES and Resend) maintaining their own server-side suppression lists.

The intended future path — when this needs to land — is webhook ingestion: `Webhooks::SesController` (SaaS, fed by SNS) and `Webhooks::ResendController` (self-hosted), both with signature verification and a `missed_email_enabled: false` flip on permanent bounces. An in-process SMTP-rescue stopgap is not the right shape — API-based delivery raises provider-specific errors (`Aws::SES::Errors::*`, `Resend::Error`) that don't reliably map to "permanent failure" the way 5xx SMTP responses do.

Subject privacy is intentional: generic subjects, no sender or room names. Sender/room names appear in the body only.

## 12. User and account defaults summary

- Existing users: `missed_email_enabled: false`, `weekly_digest_subscribed: true`, `mode: mentions_and_dms`, `push_enabled: true`, `email_frequency: hourly`. Digest defaults subscribed because it is admin-enabled with member opt-out; aggregate exposure is gated by `account.weekly_digest_enabled` defaulting `false`.
- New users: same.
- Account: `email_notifications_enabled: false`, `weekly_digest_enabled: false`. Admins flip both on.

## 13. Not currently supported

- **Thread-reply email.** Sabha already computes the right recipient set for in-app rows (thread members + parent room `involved_in_everything`, minus already-mentioned users — see `app/jobs/create_thread_reply_notifications_job.rb`); turning email on is a matter of adding `:thread_reply` to `Notification::Routing::EMAIL_TYPES` and `notification_bundle_items.kind`. Held back so a chatty thread doesn't generate one email per reply during the bundle window — needs a per-thread coalescing policy first.
- **Boost email.** No precedent in Slack or Discord; not on the roadmap.
- **Per-room email controls.**
- **Keyword alerts / custom triggers.** Treated as a separate ambient-surface product question, not part of personal notifications.
- **Marketing/news email subscriptions** (separate surface).
- **Reply-from-email.**
- **Cross-workspace bundle consolidation** — a user in three workspaces gets up to three bundles.
- **Snooze / DND / pause notifications.** Master switches (`missed_email_enabled`, `push_enabled`) and per-room `Membership#involvement: :nothing` are the only ways to silence notifications.
- **Automatic bounce/complaint suppression.** See § 11.2.
- **Personalized digest ranking** (Discord Highlights-style). Digest is a conservative recap.
- **Admin-authored digest content.** Digest is generated from workspace activity, not curated.
- **Per-user timezone digest send time.** A workspace-default day/time is used.

## 14. Notable design decisions

- **Email "away" threshold = `:away` tier (1 hour).** `workspace_locally_away?` returns true when the user's most recent connection in any of this workspace's memberships is more than `Membership::Connectable::ACTIVITY_TIERS[:away]` (1 hour) ago, or never. The tighter `:active` tier (10 minutes) was rejected: email asks "has the user been gone long enough that an email is the right way to reach them?", not "should we show a green dot?" See § 4.
- **Bundle GC = 90 days, run inside weekly digest job.** Delivered or canceled bundles older than 90 days are pruned by `Notification::Bundle.gc_terminal!` at the start of each per-tenant digest run. Active bundles are never pruned (bounded to one per user via the partial unique index in § 6.2). See § 7.6.
- **Weekly digest fires regardless of recipient activity.** A subscribed member who was active every day this week still receives the digest. Gates: `weekly_digest_subscribed: true`, account-level `weekly_digest_enabled: true`, basic user health, and 6-day dedup via `last_digest_sent_at`. A presence gate was rejected because it weakens the opt-in mental model.
- **Email provider split: SES for SaaS, Resend for self-hosted.** SaaS uses Amazon SES via `aws-sdk-rails`; self-hosted uses Resend via `resend-rails`. Both providers conform to the standard ActionMailer `delivery_method` API, so there is no provider-abstraction layer. SaaS sender domain is shared across all workspaces. See § 11.1.
- **No automatic bounce/complaint suppression today.** Bounces and complaints are not auto-ingested in the current build — exposure is bounded by `email_notifications_enabled` defaulting off. Webhook-driven suppression is sketched in § 11.2 as future work, not shipped behavior.
- **Empty digest skip does not update `last_digest_sent_at`.** `last_digest_sent_at` means "last actual delivery," not "last attempt." A member in a quiet workspace is re-evaluated next week rather than being dedup-locked through a silent stretch.
- **Stuck bundles on terminal delivery failure are marked `canceled_at`.** `BundleDeliveryJob` rescues documented terminal provider errors (e.g. `Aws::SES::Errors::MessageRejected` / `MailFromDomainNotVerified` for SES; 4xx-except-429 for Resend) and cancels the bundle, freeing the partial-unique-index slot so the user's next bundle can be created. Terminal errors do **not** flip `missed_email_enabled` — that's a per-user preference change that requires richer event data.

## 15. Glossary

- **Activity type** — symbol describing what happened to a message (`:mention`, `:direct_message`, etc.). Routing input.
- **Channel** — output target for a notification: in-app row, push, missed-notification email, weekly digest.
- **Bundle** — per-user time window that accumulates missed-notification email candidates.
- **Send-time revalidation** — re-running eligibility predicates at delivery time so state changes during the window cancel correctly.
- **Workspace-locally away** — user has no connection in *this* workspace's memberships in the last hour (`Membership::Connectable::ACTIVITY_TIERS[:away]`). Does not consider activity in other workspaces.
- **Surface** — distinct email product (missed-notification vs weekly digest). Each surface has its own opt-out and its own unsubscribe token scope.

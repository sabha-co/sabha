---
title: Sabha notifications v1 implementation
type: feat
status: active
date: 2026-05-09
origin: docs/plans/EMAIL-NOTIFICATIONS-PRD.md
architecture: docs/plans/NOTIFICATIONS-ARCHITECTURE.md
---

# Sabha notifications v1 implementation

## Overview

Implement the unified notification dispatcher and the two email surfaces (bundled missed-notification email + weekly activity digest) described in `docs/plans/NOTIFICATIONS-ARCHITECTURE.md`. The plan is phased so each unit is independently mergeable, `main` stays green throughout, and the user-visible behavior changes are gated by the account-level `email_notifications_enabled` flag (default off) until rollout.

Source of truth for **product scope**: `docs/plans/EMAIL-NOTIFICATIONS-PRD.md`.
Source of truth for **structure, components, data shapes**: `docs/plans/NOTIFICATIONS-ARCHITECTURE.md`. This plan never relitigates decisions made there — when a question reduces to "what should the data shape be" or "what is the routing matrix", look at the architecture doc. Two decisions worth flagging because they have load-bearing implications below: digest defaults to opt-out per member (arch § 6.1, § 12) and snooze is not a v1 feature in any form (arch § 4).

---

## Problem Frame

Today Sabha has three split notification decision trees: `Room::MessagePusher` (push routing), `Message` after-commit callbacks (`create_mention_notifications`, `create_thread_reply_notifications`), and "email nowhere." Adding email forces a unification pass, because every email gate (away check, account flag, master switch, block check, user health) has to live somewhere both the in-process dispatch and the delayed bundle delivery can read it.

Beyond email, the unification fixes a real structural problem: today every new channel has to plug itself into three places. After this work, `Notification::DispatchJob` + `Membership::Notifiable` are the two seams a fourth channel touches.

The PRD carves the email product into two distinct surfaces:

- **Missed-notification email** — bundled per-user, hourly or daily, only fires when the recipient is workspace-locally away. v1 candidates: DMs, direct `@mentions`, and `@everyone` / room-wide mentions (only for recipients who would receive an in-app mention row, per PRD § What generates missed-notification candidates). Thread replies, boosts, and regular room messages are out of scope (PRD § Non-goals).
- **Weekly activity digest** — admin-enabled per workspace, **opt-out per member** (members default to subscribed when admin enables; PRD § Product principles bullet 6: "weekly general-activity email is a workspace/admin choice with member opt-out"). Conservative recap of accessible activity, fires regardless of recipient activity.

The architecture doc's V0 → v1 deltas (Appendix A) are load-bearing — the v1 shape is *bundled* delivery via `Notification::Bundle` + provider-side idempotency, not per-event delayed sends with SMTP-failure rescue. Implementers arriving from the superseded `UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md` should treat that doc as eligibility/routing background only.

---

## Requirements Trace

Carried forward from `docs/plans/EMAIL-NOTIFICATIONS-PRD.md` § Goals + § Confirmed decisions and `docs/plans/NOTIFICATIONS-ARCHITECTURE.md` § 1 Goals:

- R1. **One dispatcher decides per recipient per event** across all channels (in-app, push, missed email, digest). No more split decision trees. *(arch § 1.1, § 5)*
- R2. **Bundled missed-notification email** delivered hourly or daily, user-selectable. Single email per window, not per event. *(prd § Delivery shape, § Delivery timing; arch § 7)*
- R3. **Send-time revalidation cancels stale items** at delivery (return, block, delete, opt-out). Bundle window is the cooldown — no separate per-membership cooldown column. *(arch § 7.3, § 7.5)*
- R4. **Weekly digest is a separate pipeline** with different copy, cadence, opt-out, and gates. Admin-enabled per workspace, **opt-out per member** (members default subscribed when admin enables), fires regardless of recipient activity. *(prd § Product principles #6, § Weekly activity digest, § Confirmed decisions #6, #10)*
- R5. **Tenant-safe by construction**. Per-workspace settings, per-workspace bundles, per-workspace digest. Email address is the only untenanted touchpoint via `GlobalIdentity`. *(arch § 9)*
- R6. **Default safe rollout**. Account-level `email_notifications_enabled` and `weekly_digest_enabled` default off. User-level `missed_email_enabled` defaults off (opt-in personal mail). User-level `weekly_digest_subscribed` defaults **on** (opt-out — admin enables, members already subscribed). The aggregate effect remains "no email until an admin flips the account flag," because `weekly_digest_subscribed: true` only fires when `account.weekly_digest_enabled: true`. *(prd § Product principles #6, § Defaults; arch § 6.1, § 12)*
- R7. **Provider-side idempotency** on bundle delivery — `idempotency_key: "bundle-#{bundle.id}"` so retries don't duplicate sends. *(arch § 7.7)*
- R8. **Push payload shape preserved verbatim** — same direct/shared two-branch copy as today; recipient resolution is the only thing that moves out of `Room::MessagePusher`. *(arch § 5.1)*
- R9. **Persisted `Notification.activity_type` vocabulary unchanged** — stays `%w[mention boost thread_reply]`. The dispatcher's symbol set (`mention`, `direct_message`, `everyone_room_message`, `thread_reply`, `boost`) is a strict superset for routing only. *(arch § 3)*
- R10. **Unsubscribe surface-scoped** — clicking unsubscribe in a missed-notification email does not affect digest subscription, and vice versa. RFC 8058 `List-Unsubscribe` + `List-Unsubscribe-Post` headers. *(prd § Settings; arch § 11)*
- R11. **Subject privacy** — generic subjects (no sender or room names). Sender/room names appear in body only. *(prd § Email content; arch § 11)*
- R12. **Self-hosted operators must verify a sending domain** before email turns on. Encoded by the account flag staying off until DNS is configured. *(arch § 11.1)*

Non-software origin sub-blocks (Actors / Flows / Acceptance Examples) are not present in the PRD, so omitted.

---

## Scope Boundaries

Carried verbatim from `docs/plans/EMAIL-NOTIFICATIONS-PRD.md` § Non-goals and `docs/plans/NOTIFICATIONS-ARCHITECTURE.md` § 13:

- No thread-reply email. No boost email. No regular-room-message email.
- No per-room email controls in v1.
- No keyword alerts / custom triggers.
- No marketing/news email subscriptions (separate surface).
- No reply-from-email.
- No cross-workspace bundle consolidation. A user in 3 workspaces gets up to 3 bundles.
- No snooze / DND / pause notifications. Master switches and per-room `involvement: :nothing` are the v1 silencing mechanisms.
- No personalized digest ranking (Discord Highlights-style). Digest is a conservative recap.
- No admin-authored digest content. Digest is generated from workspace activity.
- No per-user timezone digest send time. v1 uses a workspace-default day/time.
- No `Notification::PushTarget` or `Notification::*Payload` class hierarchies in v1 (Fizzy patterns deferred until divergence is real). *(arch § 5.1)*
- No `NotificationMailer` base class for two subclasses. Concern (`EmailUnsubscribable`) instead. *(arch § 11)*

### Deferred to Follow-Up Work

- **Bounce / complaint / suppression handling.** v1 ships **no** auto-suppression. v1.1 adds webhook-driven suppression via `Webhooks::SesController` (SaaS, fed by SNS) and `Webhooks::ResendController` (self-hosted). *(arch § 11.2, § 14.1)*
- **Per-workspace BYO sending domain.** v1 SaaS uses a single shared domain. v1.1 adds per-workspace domain configuration. *(arch § 11.1)*
- **Webhook ingestion controllers** (`Webhooks::SesController`, `Webhooks::ResendController`) — separate plan. *(arch § 11.2)*

---

## Context & Research

### Relevant Code and Patterns

- **Application mailer base** — `app/mailers/application_mailer.rb`. Sets `default from:` via `Branding.mailer_from`, applies `mailer` layout. Mailer view templates live in `app/views/<mailer>/` with paired `.html.erb` + `.text.erb`.
- **Representative mailer** — `app/mailers/user_mailer.rb`. `email_verification(user)`, `password_reset(user)`, etc. Plain method calls returning `mail()`.
- **Application job base** — `app/jobs/application_job.rb`. Discards on `ActiveRecord::Tenanted::TenantDoesNotExistError`. All jobs inherit this.
- **Representative async-notification job** — `app/jobs/create_thread_reply_notifications_job.rb`. `queue_as :default`, rescues `ActiveJob::DeserializationError`, performs DB queries + Turbo broadcasts inline.
- **Solid Queue recurring tasks** — `db/queue_schema.rb` defines `solid_queue_recurring_tasks` (columns: `schedule`, `class_name`, `arguments`, `static`). Configured via `config/recurring.yml` (Rails default location). No external cron.
- **Email delivery methods (already registered)** — `config/initializers/email.rb`. `ResendDeliveryMethod` and `SesDeliveryMethod` are wired as ActionMailer plugins. Default selection via `ENV["EMAIL_PROVIDER"]` (defaults `resend`). **Both delivery methods need a small extension** to read an idempotency-key header off the mail object and pass it to the provider API (see U7).
- **Account settings pattern** — `app/controllers/accounts_controller.rb` + `app/views/accounts/_admin_settings.html.erb`. Admin toggles use the `account.settings` JSON column via `fields_for :settings` with switch inputs that auto-submit on change. **Note:** the architecture doc specifies real columns (`accounts.email_notifications_enabled`, `accounts.weekly_digest_enabled`) rather than `settings` JSON — this is intentional, both because they gate background work that benefits from indexed columns and because they're not user-personalization but operational config.
- **User push subscriptions UI** — `app/controllers/users/push_subscriptions_controller.rb`. The closest existing pattern for a per-user notification preference surface; the new `Users::NotificationSettingsController` mirrors this shape.
- **Tenant entry from non-request paths** — `saas/app/models/workspace.rb:43-51`. `ApplicationRecord.with_tenant(external_id.to_s) { ... }` is the canonical wrap. Reused by the unsubscribe controller (which decodes a tenant from the token before flipping a setting) and the bundle delivery / weekly digest jobs.
- **Tenanted model setup** — `app/models/application_record.rb`. The `tenanted` macro is conditionally applied when `Sabha.saas?`. New tenanted models inherit `ApplicationRecord` directly with no extra setup.
- **Rich-text-to-plain helper** — `Message#plain_text_body` (`app/models/message.rb:108-110`). Used today by push payload formatting; reused by bundle item rendering.
- **Existing regression net** — `test/models/notification_routing_parity_test.rb` and `test/models/notification_dispatch_contract_test.rb` (added 2026-05-09). These pin recipient routing, callback ordering, scope disjointness, the `Notification.activity_type` vocabulary boundary, and the thread+mention combo case. **Both must stay green at every merge point in this plan.**
- **Fizzy prior art** — `fizzy/app/models/notification/bundle.rb`, `fizzy/app/models/notification/pushable.rb`. Reference for bundle shape and (eventually) push target hierarchy. Do not copy verbatim — Sabha's dispatcher sits at the `Message` level, not the `Notification` level (arch § 5.1).

### Institutional Learnings

- `docs/solutions/` is empty in this repo. No prior incident or pattern docs to mine.
- `AGENTS.md` reinforces RESTful controllers, fat models, and concerns over `app/services/` extraction. The plan respects this: no service-layer objects, all logic on `Message`, `Membership`, `Notification::Bundle`, etc.

### External References

The architecture doc and PRD already absorbed the relevant external research (Slack notification docs, Discord notification docs, RFC 8058 `List-Unsubscribe`, SES vs Resend tradeoffs, idempotency-key semantics). No additional external research needed.

---

## Key Technical Decisions

These are the decisions this plan locks in *beyond* what the architecture doc settles. Decisions made by the architecture doc (e.g., bundle two-table shape, `:away` 1-hour tier, SES/Resend split, no provider abstraction) are referenced, not relitigated.

- **Plan filename follows repo convention**, not the `YYYY-MM-DD-NNN-` convention from the planning skill template. Existing plans (`BOT-API-CANONICAL-SURFACE-PLAN.md`, `ID-ONLY-BOT-MESSAGE-OPS-PLAN.md`, `EMAIL-NOTIFICATIONS-PRD.md`) all use `UPPER-CASE-DESCRIPTION.md`. Following that convention here.
- **`Notification::DispatchJob` is the new dispatcher seam, even though `Notification` is also a model name.** The job is namespaced under the `Notification` model module (Rails autoloads `Notification::DispatchJob` from `app/jobs/notification/dispatch_job.rb`). Same for `Notification::Bundle`, `Notification::BundleItem`, `Notification::BundleDeliveryJob`, `Notification::WeeklyDigestJob`, `Notification::Routing`. Co-locates routing/bundling code under one namespace and makes file paths predictable.
- **Reuse the existing `ResendDeliveryMethod` / `SesDeliveryMethod` plugins** instead of replacing them. Both need a one-method extension to read an idempotency-key header off the `Mail::Message` and pass it to the provider API. No `Notification::EmailProvider` abstraction (arch § 11.1).
- **Bundle delivery's idempotency-key transport is a custom mail header** (`X-Idempotency-Key: bundle-<id>`), set by the mailer and read by both delivery methods. ActionMailer doesn't have a generic provider-arg passthrough; a header is the cleanest carrier. The header is stripped from the outgoing message body in both delivery methods.
- **Mailer base for the two surfaces is `ApplicationMailer` directly** (arch § 11). Both mailers `include EmailUnsubscribable`. No `NotificationMailer` intermediate.
- **`Notification::Routing` is a plain module of frozen constants**, not an ActiveSupport::Concern, not an enum. The constants are referenced by `Membership::Notifiable` predicates and by `Message#applicable_activity_types`. A module with `freeze`d arrays is the simplest carrier and matches DHH-style restraint.
- **Settings backfill runs in a data migration** that uses `User.where.missing(:notification_settings).find_each(&:create_notification_settings!)`. Idempotent — re-runnable safely. Lives in `db/migrate/<timestamp>_backfill_user_notification_settings.rb` so it composes with the schema migration in U2.
- **Digest send day defaults to Tuesday 10:00 UTC.** The PRD defers to product default; the architecture doc § 14.2 leaves it open. Tuesday avoids Monday inbox crush and Friday-pre-weekend dropoff. UTC is workspace-default for v1 (per-workspace TZ deferred to v1.1 per arch § 13). This is configured as a recurring task in `config/recurring.yml`, not hard-coded — admin-customizable send time is a v1.1 concern.
- **"Notification-worthy" in digest content selection (arch § 14.2 open question)** = `@everyone` mentions only, in v1. Named mentions are already covered by the missed-notification surface; including them in digest creates surface overlap. Revisit in v1.1 if subscribed-but-active members report missing context.
- **Bundle item join cost (arch § 14.2 open question)** is acceptable at expected v1 volumes (consenting workspaces, small membership counts). The query plan is `bundle_items` filtered by `bundle_id`, joined to `messages` for room/active checks and to `memberships` for revalidation. With the `(bundle_id, message_id, kind)` unique index and one-active-bundle-per-user partial unique index (arch § 6.2), the per-job working set is bounded by the hourly-or-daily window's mention/DM volume per user. v1.1 revisits if a chatty workspace surfaces > 1s job runtime.
- **Push routing relocation does not change `Membership.involved_in_everything` / `.involved_in_mentions` scopes.** The scopes stay on `Membership` (existing); only their *invocation site* moves from `Room::MessagePusher` to `Message#push_recipient_user_ids_for(activity_type)` (arch § 5.1).
- **Boost dispatch keeps its inline path until U4 lands.** Until the dispatcher exists, leaving `Boost#create_boost_notification` as-is is correct. U4 is the moment boost moves to `Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)`.

---

## Open Questions

### Resolved During Planning

- **Bundle frequency change mid-window** *(arch § 14.2)*. Resolved: in-flight bundles keep their original `frequency` (snapshotted at bundle creation, see arch § 6.2). Next bundle uses the new preference. Matches the simplest-correct shape and decouples in-flight delivery from preference flips.
- **Digest send day/time** *(arch § 14.2)*. Resolved: Tuesday 10:00 UTC default, configured in `config/recurring.yml`. Per-workspace TZ deferred to v1.1.
- **`@everyone` digest weighting** *(arch § 14.2)*. Resolved: `@everyone` mentions only; named mentions stay on the missed-notification surface to avoid overlap.
- **Backfill behavior on deploy** *(arch § 14.2)*. Resolved: idempotent `find_each(&:create_notification_settings!)` run in a data migration alongside the schema migration in U2.

### Deferred to Implementation

- **Exact bundle delivery query shape** *(arch § 14.2)*. The join `bundle_items × messages × memberships` is bounded but exact SQL shape (eager-load vs. join, what to select) is best decided when writing `BundleDeliveryJob#deliverable_items` against real fixtures in U6. Plan accepts that the partial unique index on bundles + the `(bundle_id, message_id, kind)` unique on items keep the working set tight.
- **Custom-header idempotency-key passthrough integration tests.** Whether to verify Resend / SES actually dedup on retry (vs. trust documented behavior + unit-test header passthrough) depends on what the test environment supports. Default is unit-level header verification; integration smoke tests are nice-to-have, not blocking.
- **Settings UI design specifics.** Field labels, copy, ordering, and the visual shape of the "manage email" page are deferred to U7 — once the controller surface exists, the view follows the existing `app/views/users/push_subscriptions/` pattern.
- **Empty digest skip vs. send.** Architecture § 14.1 commits to *skip-without-touching-`last_digest_sent_at`*. Confirmed at planning time. Implementation in U8 just enforces it; no further design needed.

---

## High-Level Technical Design

> *This illustrates the intended data and dispatch flow at the seam where the most behavior changes (U4–U6). It is directional guidance for review, not implementation specification.*

```
Message create / Boost create / Thread reply
        │
        ▼
Notification::DispatchJob.perform_later(message[, only:, actor:])    ← U4
        │
        ▼
Message#notify_recipients(only:, actor:)
        │
        ├── for each activity_type in Room#applicable_activity_types(message):
        │       │
        │       ├──▶ create_notification_rows_for(activity_type)            ← in-app rows
        │       │       (mention/boost/thread_reply only — Notification.activity_type vocab)
        │       │
        │       ├──▶ deliver_push_for(activity_type)                        ← push
        │       │       Recipient resolution: Membership::Notifiable#receives_push_for?
        │       │       Payload: Room::MessagePusher#build_payload (unchanged)   [arch § 5.1]
        │       │
        │       └──▶ enqueue_missed_email_candidates_for(activity_type)     ← bundle add  ← U5
        │               for each Membership::Notifiable#receives_missed_email_for?
        │                   bundle = Notification::Bundle.find_or_create_active_for(user)
        │                   Notification::BundleItem.create!(bundle:, message:, kind:, actor:)
        │                   (partial unique index handles race; insert race retries)
        │
        ▼
(time passes — bundle.ends_at fires the scheduled job)
        ▼
Notification::BundleDeliveryJob#perform(bundle)                              ← U6
        │
        ├── re-eval each item via Membership::Notifiable#receives_missed_email_for?
        │       │
        │       ├── all items dropped → bundle.canceled_at = now; exit
        │       └── items remain     → MissedNotificationsMailer.bundle(user, items).deliver_now    ← U7
        │                              with header X-Idempotency-Key: "bundle-#{bundle.id}"
        │                              bundle.delivered_at = now
        │
        └── rescue terminal provider errors (arch § 14.1) → bundle.canceled_at = now
            transient errors propagate → Solid Queue retries

(independent pipeline — U8)
Notification::WeeklyDigestJob (cron, weekly per workspace)
        │
        ▼
Notification::Bundle.where(...older than 90 days, terminal).delete_all       ← bundle GC (arch § 7.6)
        │
        ▼
For each subscribed member where last_digest_sent_at < 6.days.ago:
    content = digest_content_for(user)
    next if content.empty?
    WeeklyDigestMailer.digest(user, content).deliver_now
    user.notification_settings.update!(last_digest_sent_at: Time.current)
```

The `Notification::Routing` module gates which channel each `activity_type` enters. `Membership::Notifiable` predicates gate which *recipient* sees a given `(message, activity_type)` pair. The two are orthogonal — adding a fifth channel edits `Notification::Routing` first, then the predicate that consumes it.

---

## Implementation Units

The plan unfolds in seven phases. Each unit ends in a mergeable state with `main` green. Behavior changes are gated by the account-level flags introduced in U3 (default off) until rollout.

### Phase 1: Foundation (no behavior change)

- U1. **`Notification::Routing` constants + `Membership::Notifiable` extraction + `Membership#effective_involvement`**

**Goal:** Establish the routing vocabulary and recipient-eligibility seam without changing any current behavior. Existing code paths still drive in-app rows and push exactly as today; this unit just makes the seams nameable.

**Requirements:** R1, R8, R9.

**Dependencies:** None. Builds directly on the existing regression net (`test/models/notification_routing_parity_test.rb`, `test/models/notification_dispatch_contract_test.rb`).

**Files:**
- Create: `app/models/notification/routing.rb`
- Create: `app/models/membership/notifiable.rb`
- Modify: `app/models/membership.rb` (include `Notifiable`, add `effective_involvement`)
- Test: `test/models/notification/routing_test.rb`
- Test: `test/models/membership/notifiable_test.rb`
- Test: `test/models/membership_test.rb` (add `effective_involvement` cases)

**Approach:**
- `Notification::Routing` is a frozen-constant module with `ACTIVITY_TYPES`, `IN_APP_ROW_TYPES`, `PUSH_TYPES`, `EMAIL_TYPES` exactly as listed in arch § 3. No methods, no concern, no enum.
- `Membership::Notifiable` is an `ActiveSupport::Concern`. v1 predicates: `receives_in_app_row_for?(message, activity_type)`, `receives_push_for?(message, activity_type)`, `receives_missed_email_for?(message, activity_type)`, `receives_digest?`. The email and digest predicates can return false unconditionally for now (account flag is off, user setting defaults off, no settings table yet) — this unit is structural; U2/U3 supply the data.
- `Membership#effective_involvement` returns `:everything` if per-room `involvement == "everything"`; `:nothing` if global `mode == "nothing"` (read from `user.notification_settings&.mode`, falls back to `:mentions_and_dms` when the settings row doesn't exist yet); else the per-room `involvement`. Settings row absence is fine — falls back to default mode behavior, which preserves current semantics.
- Predicate bodies reference the existing `Membership` state plus `Notification::Routing` constants. No call-site changes in this unit — `Room::MessagePusher` and `Message#create_mention_notifications` keep their inline checks. The seam exists, but isn't yet load-bearing.

**Execution note:** Characterization-first. The two existing parity/contract test files already lock the behavior we must preserve. Run them after every step in this unit to confirm nothing has shifted.

**Patterns to follow:**
- `app/models/message/mentionee.rb` — concern shape and naming.
- Existing `Membership` predicates (`receives_mentions?`, `read?`) for predicate naming style.

**Test scenarios:**
- *Happy path:* `Notification::Routing::EMAIL_TYPES` returns `[:mention, :direct_message]` and is frozen.
- *Happy path:* `IN_APP_ROW_TYPES`, `PUSH_TYPES`, `ACTIVITY_TYPES` match arch § 3 verbatim.
- *Happy path:* `Membership::Notifiable#receives_in_app_row_for?(mention)` returns true for an active visible non-creator member with `involvement: mentions`.
- *Edge case:* `receives_in_app_row_for?` returns false when the member is the message creator.
- *Edge case:* `receives_in_app_row_for?` returns false when the membership is `invisible`.
- *Edge case:* `effective_involvement` returns `:everything` for a per-room `everything` membership even when the user's `mode == "nothing"` (per-room override beats global mute, arch § 4 rule 1).
- *Edge case:* `effective_involvement` returns `:nothing` when global `mode == "nothing"` and per-room is `mentions` (rule 2).
- *Edge case:* `effective_involvement` returns the per-room value when no `notification_settings` row exists yet (rule 3 default-fallback).

**Verification:**
- `bin/rails test test/models/notification_routing_parity_test.rb test/models/notification_dispatch_contract_test.rb` is green.
- `bin/rails test test/models/notification/routing_test.rb test/models/membership/notifiable_test.rb` is green.
- `Notification::Routing` and `Membership::Notifiable` are reachable via Rails autoload (`bin/rails runner 'puts Notification::Routing::EMAIL_TYPES'`).
- `SAAS=true bin/rails test saas/test/` is green.

---

### Phase 2: Settings infrastructure

- U2. **`User::NotificationSettings` model + migration + idempotent backfill**

**Goal:** Persist per-user notification preferences in a real, indexed table. Defaults match arch § 12 so existing users get safe values on backfill.

**Requirements:** R5, R6.

**Dependencies:** U1 (Membership::Notifiable predicates reference `user.notification_settings`).

**Files:**
- Create: `db/migrate/<timestamp>_create_user_notification_settings.rb`
- Create: `db/migrate/<timestamp+1>_backfill_user_notification_settings.rb` (data migration)
- Create: `app/models/user/notification_settings.rb`
- Modify: `app/models/user.rb` (`has_one :notification_settings, class_name: "User::NotificationSettings", dependent: :destroy`, `after_create_commit :build_default_notification_settings`)
- Modify: `app/models/user.rb` `destroy_all_associated_records` (delete settings)
- Test: `test/models/user/notification_settings_test.rb`
- Test: `test/models/user_test.rb` (settings auto-created on user creation)

**Approach:**
- Schema columns match arch § 6.1 verbatim: `user_id` (references, unique), `mode` (string, default `mentions_and_dms`), `missed_email_enabled` (bool, default `false`), `email_frequency` (string, default `hourly`), `weekly_digest_subscribed` (bool, default `true`), `push_enabled` (bool, default `true`), `last_digest_sent_at` (datetime, nullable). The U2 backfill creates settings rows for existing users with these defaults — every existing member starts digest-subscribed, ready to receive the digest the moment an admin flips `account.weekly_digest_enabled`.
- `mode` and `email_frequency` use Rails `enum` with explicit string mapping (`enum :mode, %w[nothing mentions_and_dms all].index_by(&:itself)`). `index_by(&:itself)` mirrors the `Membership#involvement` pattern at `app/models/membership.rb:35`.
- New users get a settings row via an `after_create_commit` callback that calls `create_notification_settings!` if missing. Building it eagerly in a callback is simpler than lazy-creating from `Membership::Notifiable` predicates and matches the architecture doc's "built on user creation" note.
- Backfill data migration: `User.unscoped.where.missing(:notification_settings).find_each(&:create_notification_settings!)`. Idempotent. Runs in the same deploy as the schema migration.
- The model is tenanted (inherits `ApplicationRecord`). In SaaS, each workspace's tenant DB has its own `user_notification_settings` table. A user in workspaces A and B has independent settings rows in each (arch § 9).

**Execution note:** Migrations land first; the model + callback land in the same PR so tests aren't briefly red.

**Patterns to follow:**
- `app/models/user.rb:7-30` for `serialize`, enum, association style.
- `app/models/membership.rb:35` for `enum` declaration with explicit `index_by(&:itself)`.

**Test scenarios:**
- *Happy path:* `User.create!(...)` synchronously creates a `notification_settings` row with default values matching arch § 12.
- *Happy path:* `user.notification_settings.mode` defaults to `mentions_and_dms`.
- *Happy path:* `user.notification_settings.email_frequency` defaults to `hourly`.
- *Happy path:* `user.notification_settings.weekly_digest_subscribed` defaults to **`true`** (opt-out semantics per PRD § Product principles #6).
- *Happy path:* `user.notification_settings.missed_email_enabled` defaults to `false` (opt-in for personal mail).
- *Edge case:* Rapid double-create of a user does not raise on the unique `user_id` index (callback only fires once due to `after_create_commit`).
- *Integration:* The backfill data migration creates settings rows for users that pre-date the schema migration without creating duplicates for users that already have one.
- *Integration:* `user.destroy` cleans up the settings row (covered by `dependent: :destroy` and `destroy_all_associated_records`).

**Verification:**
- `bin/rails db:migrate` runs cleanly; rerunning the backfill is a no-op.
- `bin/rails test test/models/user/notification_settings_test.rb` is green.
- `bin/rails test` (full self-hosted) is green.
- `SAAS=true bin/rails test saas/test/` is green — tenanted setup applies correctly.

---

- U3. **Account-level email and digest flags**

**Goal:** Add the two account-scoped feature flags (`email_notifications_enabled`, `weekly_digest_enabled`) and surface them in the existing admin settings page. Both default off.

**Requirements:** R6, R12.

**Dependencies:** U2 (admin UI may reference user-side settings copy in the same view session).

**Files:**
- Create: `db/migrate/<timestamp>_add_email_flags_to_accounts.rb`
- Modify: `app/models/account.rb` (no new logic needed beyond column, but document defaults)
- Modify: `app/views/accounts/_admin_settings.html.erb` (add two switches)
- Modify: `app/controllers/accounts_controller.rb` `account_params` (permit the two new columns)
- Test: `test/controllers/accounts_controller_test.rb` (admin can flip both; non-admin cannot)
- Test: `test/models/account_test.rb` (defaults)

**Approach:**
- Real columns, not `account.settings` JSON, because they gate background work (the dispatcher reads `account.email_notifications_enabled?` per email candidate). Indexed boolean reads beat JSON extraction. Architecture doc § 6.4 makes the same call.
- Admin UI follows the existing `_admin_settings.html.erb` pattern — `fields_for` + hidden field toggle pair + switch input with `data-action="change->form#submit"`. Both flags ship in the same form section, labeled clearly so admins understand the difference between "missed-notification email" and "weekly digest."
- For self-hosted, the admin-settings page should display a small inline note explaining that flipping `email_notifications_enabled` requires a verified Resend domain (arch § 11.1). The note is a short paragraph above the toggle, not a separate page.

**Execution note:** None — this is conventional admin-UI work.

**Patterns to follow:**
- `app/views/accounts/_admin_settings.html.erb` — switch pattern, instant-submit pattern.
- `app/controllers/accounts_controller.rb` — strong params.

**Test scenarios:**
- *Happy path:* `Account.sole.email_notifications_enabled` defaults to `false`.
- *Happy path:* `Account.sole.weekly_digest_enabled` defaults to `false`.
- *Happy path:* Admin updates the flag via PATCH `/account`; reloaded record reflects the change.
- *Error path:* Non-admin user attempting the same PATCH receives a 403 / redirect (matches existing accounts controller pattern).
- *Edge case:* Flag column is queryable as a SQL boolean without JSON extraction.

**Verification:**
- `bin/rails db:migrate` runs cleanly.
- `bin/rails test test/controllers/accounts_controller_test.rb test/models/account_test.rb` is green.
- Visiting `/account` as an admin shows both new toggles, default off, with the self-hosted setup note when applicable.
- `SAAS=true bin/rails test saas/test/` is green — the `accounts` migration runs across all tenants via `db:migrate:primary`.

---

### Phase 3: Dispatch consolidation

- U4. **`Notification::DispatchJob` + `Message#notify_recipients` + push routing relocation + boost dispatch via job**

**Goal:** Single dispatch job orchestrates in-app rows, push, and (in U5) bundle candidates per message. Push recipient resolution moves from `Room::MessagePusher` to `Message`. Boost dispatch enters the same job with `only: :boost, actor: booster`. **No user-visible behavior change** — same recipients, same payloads, same Notification rows. The existing parity tests are the contract.

**Requirements:** R1, R8, R9.

**Dependencies:** U1 (predicates), U2 (settings exist for predicate fallbacks even though email is gated off).

**Files:**
- Create: `app/jobs/notification/dispatch_job.rb`
- Modify: `app/models/message.rb` (add `notify_recipients`, `push_recipient_user_ids_for`, `dispatch_notifications` callback; keep existing callbacks intact for now)
- Modify: `app/models/room.rb` (add `applicable_activity_types(message)`)
- Modify: `app/models/room/message_pusher.rb` (narrow to payload formatting; delete the `push_to_users_*` methods, expose `build_payload` as a public method or class-method wrapper)
- Modify: `app/models/boost.rb` (replace inline `Notification.create!` with `Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)`; keep the DM/thread suppression logic on `Boost`)
- Test: `test/jobs/notification/dispatch_job_test.rb`
- Test: `test/models/message_test.rb` (add `notify_recipients` and `push_recipient_user_ids_for` cases)
- Test: `test/models/room/message_pusher_test.rb` (add — payload-only contract)

**Approach:**
- `Notification::DispatchJob.perform(message, only: nil, actor: nil)` calls `message.notify_recipients(only:, actor:)`. ActiveJob serializes/deserializes both records via GlobalID transparently (the gem also belt-and-suspenders carries the tenant). `discard_on ActiveJob::DeserializationError` per the existing job pattern handles the deleted-message case.
- `Message#notify_recipients(only: nil, actor: nil)`:
  - If `only:` is set, runs only that activity_type.
  - Otherwise, iterates `room.applicable_activity_types(self)` and runs the three channel branches (`create_notification_rows_for`, `deliver_push_for`, `enqueue_missed_email_candidates_for`). For U4, the email branch is a no-op stub — U5 wires it.
- `Room#applicable_activity_types(message)` returns the routing-vocabulary symbols that apply to this message in this room. For example, `Rooms::Direct` returns `[:direct_message]` plus `[:mention]` iff the message has named mentions; `Rooms::Open` returns `[:mention]` if `mentions_everyone?` is true OR `mentionees.any?`, plus `[:everyone_room_message]` if `mentions_everyone?`. Encapsulates the room-type fan-out so `Message#notify_recipients` doesn't branch on `room.is_a?(Rooms::Direct)`.
- `Message#push_recipient_user_ids_for(activity_type)` returns the candidate user IDs per arch § 5.1. The existing `Membership.involved_in_everything` and `Membership.involved_in_mentions` scopes still drive the disjoint subsets — invocation moves from `Room::MessagePusher` to `Message`. `Membership::Notifiable#receives_push_for?` filters per recipient.
- `Message#deliver_push_for(activity_type)` builds the payload via `Room::MessagePusher.new(room:, message:).build_payload` (or a class-method `Room::MessagePusher.payload_for(room:, message:)` if the class-method shape feels cleaner) and queues delivery through `Rails.configuration.x.web_push_pool` exactly as today. Payload shape is unchanged (R8).
- `dispatch_notifications` is a new `after_create_commit` callback on `Message`, **declared after** `create_thread_reply_notifications` (line 25 of `app/models/message.rb`). The dispatch contract test in `test/models/notification_dispatch_contract_test.rb` enforces this ordering — if the test fails, the callback is in the wrong place.
- The legacy `create_mention_notifications` callback is **kept intact for U4**. The job's `create_notification_rows_for(:mention)` is a no-op pass-through that delegates to the existing `create_mention_notifications` results — until U5 makes the dispatcher fully responsible. Avoiding double-write of mention rows here is critical: the dispatch job sees that mention rows already exist (via the partial unique index `index_notifications_on_message_user_type` referenced at `app/models/message.rb:280`) and skips. Documented in code comments inside `notify_recipients`.
- Boost path: `Boost#create_boost_notification` becomes `Boost#dispatch_notification` and calls `Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)`. The DM/thread suppression check stays on `Boost` (early return — the dispatch job never gets called). The job's boost branch creates the same `Notification` row + Turbo broadcast that the inline path did.

**Execution note:** Characterization-first. The existing parity tests (`notification_routing_parity_test.rb`, `notification_dispatch_contract_test.rb`) are the contract. Every commit in this unit must keep them green. The new tests in this unit are about the *new seam* (dispatch job, `notify_recipients`, payload-only `MessagePusher`); they don't replace the parity tests.

**Patterns to follow:**
- `app/jobs/create_thread_reply_notifications_job.rb` — async-notification job shape, including `discard_on` and explicit error rescue.
- `app/models/room/message_pusher.rb` — payload formatting stays here verbatim; just lose the routing methods.
- `Notification::DispatchJob` boost path mirrors today's `Boost#create_boost_notification` (`app/models/boost.rb:26-44`).

**Test scenarios:**
- *Happy path (parity):* All scenarios in `test/models/notification_routing_parity_test.rb` stay green. This is the contract.
- *Happy path:* Sending a message in `Rooms::Designers` enqueues `Notification::DispatchJob` exactly once (no per-activity-type duplication).
- *Happy path:* The dispatch job's push delivery for a regular message reaches the same user IDs as today's `Room::MessagePusher#push` (`user_ids(:jason, :jz)` for the existing fixture).
- *Happy path:* The dispatch job's boost branch (`only: :boost`) creates a `Notification` with `activity_type: "boost"`, `actor_id: booster.id`, `user_id: message.creator_id` — matching today's inline path.
- *Edge case:* A message that is both a mention and `@everyone` (mentions_everyone + named mention) does not double-push the named mentioned user.
- *Edge case:* A boost on a DM or DM-thread message creates no `Notification` row (suppression preserved on `Boost` before job enqueue).
- *Error path:* The dispatch job discards when given a deleted message (`ActiveJob::DeserializationError`).
- *Integration:* The new `dispatch_notifications` callback fires after `create_thread_reply_notifications` (locked by `notification_dispatch_contract_test.rb`).
- *Integration:* `Room::MessagePusher` exposes only payload formatting; calling `push` on it is no longer the routing entry point. (Optional belt-and-suspenders test: assert the routing methods are gone.)
- *Integration (SaaS):* every Turbo broadcast emitted by the dispatch job uses a tenanted model as its first argument (e.g. `[user, :inbox_activity]`, `Current.account`), never a bare symbol. Per the Sabha addendum to the activerecord-tenanted guide, bare-symbol streams produce identical names across tenants and would leak. Test asserts a broadcast in tenant A is not received by a stream subscriber in tenant B.

**Verification:**
- `bin/rails test test/models/notification_routing_parity_test.rb test/models/notification_dispatch_contract_test.rb test/models/notification_test.rb` is green.
- `bin/rails test test/jobs/notification/dispatch_job_test.rb test/models/message_test.rb test/models/room/message_pusher_test.rb` is green.
- `bin/rails test` and `SAAS=true bin/rails test saas/test/` both green. SaaS run includes the cross-tenant Turbo broadcast scoping test.
- Manual smoke: send a message in dev, see it broadcast + push exactly as before; no duplicate Notification rows; no missing rows.

---

### Phase 4: Bundle pipeline

- U5. **Bundle schema + models + candidate creation in dispatcher**

**Goal:** Persist per-user bundle windows and append items as eligible mentions/DMs occur. Bundle delivery is **not** wired yet — items accumulate, but no email goes out until U6 (and even then, the account flag gates exposure).

**Requirements:** R2, R3, R5.

**Dependencies:** U1, U2, U3, U4.

**Files:**
- Create: `db/migrate/<timestamp>_create_notification_bundles.rb`
- Create: `db/migrate/<timestamp+1>_create_notification_bundle_items.rb`
- Create: `app/models/notification/bundle.rb`
- Create: `app/models/notification/bundle_item.rb`
- Modify: `app/models/message.rb` (replace U4 stub `enqueue_missed_email_candidates_for(activity_type)` with real implementation)
- Modify: `app/models/membership/notifiable.rb` (`receives_missed_email_for?` reads `user.notification_settings.missed_email_enabled?`, `account.email_notifications_enabled?`, `user.workspace_locally_away?`, `Notification::Routing::EMAIL_TYPES.include?(activity_type)`)
- Modify: `app/models/membership/connectable.rb` (add `User#workspace_locally_away?` or `Membership.workspace_locally_away?(user)`)
- Test: `test/models/notification/bundle_test.rb`
- Test: `test/models/notification/bundle_item_test.rb`
- Test: `test/models/membership/notifiable_test.rb` (extend with email predicate cases)
- Test: `test/models/message_test.rb` (extend — bundle item creation under enabled flags)

**Approach:**
- Schema matches arch § 6.2 + § 6.3 verbatim. Critical: the **partial unique index** `(user_id) WHERE delivered_at IS NULL AND canceled_at IS NULL` makes "at most one active bundle per user" a DB invariant. SQLite supports partial unique indexes — verify in the migration.
- `Notification::Bundle.find_or_create_active_for(user)`: query for active bundle; if none, insert a new one with `frequency` snapshotted from `user.notification_settings.email_frequency` and `ends_at = starts_at + frequency_window`. Wrap the insert in a `rescue ActiveRecord::RecordNotUnique → retry the read` block so two simultaneous Message creates can't race-create two active bundles. **U6 schedules `BundleDeliveryJob` with `wait_until: ends_at`; this unit doesn't enqueue delivery yet** — items just accumulate.
- `frequency_window`: hourly → 1.hour, daily → 24.hours. Constant on `Notification::Bundle`.
- `Notification::BundleItem.belongs_to :bundle`. `belongs_to :message`. `belongs_to :actor, class_name: "User"`. `kind` is a string (`"mention"` / `"direct_message"`) — **not** the same vocabulary as `Notification.activity_type` (arch § 6.3).
- `Notification::Bundle has_many :items, class_name: "Notification::BundleItem", dependent: :delete_all`. The cascade matters for U6 (terminal-cancel) and U8 (GC).
- `User#workspace_locally_away?` (or `Membership.workspace_locally_away?(user_id)`): true when `Membership.last_connected_at_for([user_id])` is more than `Membership::Connectable::ACTIVITY_TIERS[:away]` (1 hour) ago, or never. This is the email-only presence check — push still uses the 60-second `connected?` (arch § 4).
- `Message#enqueue_missed_email_candidates_for(activity_type)`: for each candidate recipient, check `membership.receives_missed_email_for?(message, activity_type)`. If true, find-or-create the bundle and insert a `BundleItem` with `unique_by: %i[bundle_id message_id kind]` (unique index handles within-bundle dedup). The candidate set per activity_type:
  - `:mention` candidates **= the same recipients that get in-app mention rows** (PRD § What generates missed-notification candidates: "`@everyone` / room-wide mentions, only when the user would receive an in-app mention row"). Concretely: `message.mentions_everyone? ? room.user_ids - [creator_id] : message.mentionee_ids - [creator_id]`. Mirrors the row-recipient computation in `app/models/message.rb:267-271`. **`@everyone` candidates are not separately enumerated** — they ride the same `:mention` candidate set as named mentions, because `Message::Mentionee#mentionees` already returns `room.users` for `@everyone` messages (`app/models/message/mentionee.rb:17-26`). The `kind: "mention"` BundleItem covers both broad and named mentions; the per-recipient predicate then narrows to recipients who would receive an in-app row.
  - `:direct_message` candidates = the other DM party (i.e. the non-creator member of `room.memberships`). These do not produce in-app rows but do produce email candidates per arch § 3.
  - `:everyone_room_message` and `:thread_reply` produce no email candidates (`Notification::Routing::EMAIL_TYPES` excludes them).

**Execution note:** Test-first for `Bundle.find_or_create_active_for` — the race-retry path is the easy one to get wrong. Add a test that simulates a race by stubbing the first `find_by` to return nil, then asserts the second insert raises `RecordNotUnique` and the retry succeeds.

**Patterns to follow:**
- `app/models/membership/connectable.rb` — `last_connected_at_for` shape and `ACTIVITY_TIERS` constant.
- `app/models/message.rb:276` — `Notification.insert_all(..., unique_by: ...)` for race-safe bulk inserts.

**Test scenarios:**
- *Happy path:* A mention to an away user with `missed_email_enabled: true` and `account.email_notifications_enabled: true` creates a `BundleItem` with `kind: "mention"` in a new active bundle.
- *Happy path:* An `@everyone` message in an open room creates `kind: "mention"` BundleItems for every away room member who would receive an in-app row (i.e. all members minus creator, then filtered by `receives_missed_email_for?`). Locks PRD § What generates missed-notification candidates.
- *Happy path:* A DM to an away user creates a `BundleItem` with `kind: "direct_message"`.
- *Happy path:* Multiple mentions in the same window land in the same bundle (single bundle row per user-window).
- *Happy path:* `frequency` on the bundle reflects the user's preference at bundle creation; later flips don't move the bundle.
- *Edge case:* A mention to a non-away user (connected within the last hour) creates no bundle item.
- *Edge case:* A mention with `account.email_notifications_enabled: false` creates no bundle item.
- *Edge case:* A mention with `user.notification_settings.missed_email_enabled: false` creates no bundle item.
- *Edge case:* A blocked-sender mention creates no bundle item (predicate's block check).
- *Edge case:* The same `(message, kind)` pair is not duplicated in the bundle — second insert hits the unique index, second insert is a no-op or rescue-and-skip.
- *Error path:* Two simultaneous DMs to the same away user (race) result in one bundle, two items. The partial unique index forces one of the inserts to retry the read.
- *Integration:* `User#workspace_locally_away?` returns true when no membership in the workspace has `connected_at` in the last hour, false otherwise.

**Verification:**
- `bin/rails db:migrate` runs cleanly; partial unique indexes are present (verify in `db/schema.rb`).
- All bundle/item tests green.
- Existing parity + dispatch contract tests stay green.
- `SAAS=true bin/rails test saas/test/` is green — bundle creation respects per-tenant DB.
- Manual smoke: send a message to an "away" user (set `connected_at` to 2 hours ago), enable both flags, observe a `notification_bundle_items` row appears.

---

- U6. **`Notification::BundleDeliveryJob` — revalidation, idempotency, terminal-error rescue**

**Goal:** When a bundle's `ends_at` arrives, deliver an email containing items that are still eligible. Cancel the bundle if all items drop. Provider-side idempotency keeps retries safe.

**Requirements:** R3, R7.

**Dependencies:** U5.

**Files:**
- Create: `app/jobs/notification/bundle_delivery_job.rb`
- Modify: `app/models/notification/bundle.rb` (add `terminal?`, `cancel!`, schedule helper that `BundleDeliveryJob.set(wait_until: ends_at).perform_later(self)`)
- Modify: `app/models/message.rb` `enqueue_missed_email_candidates_for` — schedule the delivery job once when the bundle is freshly created (not on every item add).
- Test: `test/jobs/notification/bundle_delivery_job_test.rb`
- Test: `test/models/notification/bundle_test.rb` (extend — terminal helpers)

**Approach:**
- `BundleDeliveryJob#perform(bundle)`: discard on `ActiveJob::DeserializationError`. Skip if `bundle.terminal?` (delivered/canceled — protects against duplicate scheduling). Walk `bundle.items.includes(:message, :actor)`, ask `membership.receives_missed_email_for?(item.message, item.kind.to_sym)` for each. Drop items the predicate rejects.
- If no items remain, set `canceled_at: Time.current` and exit.
- If items remain, call `MissedNotificationsMailer.bundle(user, items).deliver_now` (sync inside the job — the job *is* the async boundary). On success, set `delivered_at: Time.current`.
- Provider-side idempotency: the mailer adds an `X-Idempotency-Key: bundle-#{bundle.id}` header. U7 wires the delivery methods to read and consume it. Because the key is stable across retries, a retry after a transient failure deduplicates server-side and the mailer call returns without re-sending; the retry then sets `delivered_at` again (idempotent at DB level — same value, same row).
- Terminal-error rescue per arch § 14.1: rescue `Aws::SES::Errors::MessageRejected`, `Aws::SES::Errors::MailFromDomainNotVerified` (SES) and a defined list of Resend 4xx-except-429 errors (the existing `ResendDeliveryMethod` raises a `Resend::Error` subclass — list the exact subclasses to catch). On a terminal error, set `canceled_at: Time.current` and re-raise as a custom `Notification::BundleDeliveryJob::TerminalError` for observability. Transient errors (5xx, timeouts, rate limits) propagate as-is so Solid Queue retries.
- **Bundle scheduling moves from per-item to per-bundle.** `Message#enqueue_missed_email_candidates_for` checks `bundle.previously_new_record?` (or equivalent) on the find-or-create result and schedules the delivery job exactly once when a bundle is freshly created.

**Execution note:** Test-first. The revalidation fan-out, the idempotency-key passthrough, and the terminal-error rescue are all easy to get wrong; tests pin them.

**Patterns to follow:**
- `app/jobs/create_thread_reply_notifications_job.rb` — discard_on, explicit rescue boundaries.
- The existing two-pass pattern in `Notification.delete_all_and_broadcast` (`app/models/notification.rb:29-50`) for "load, evaluate, mutate" shape.

**Test scenarios:**
- *Happy path:* A bundle with three items, all still eligible, calls `MissedNotificationsMailer.bundle` once with all three items and sets `delivered_at`.
- *Happy path:* `BundleDeliveryJob` is enqueued exactly once when a new bundle is created (not on each item insert).
- *Happy path:* The mailer call receives the `X-Idempotency-Key: bundle-<id>` header on the `Mail::Message`.
- *Edge case:* All items dropped (user reconnected mid-window) → bundle is `canceled_at`, no email sent, `delivered_at` is nil.
- *Edge case:* Two items eligible, one dropped (sender just blocked recipient) → one email with two items.
- *Edge case:* `bundle.terminal?` returns true for delivered or canceled bundles; `BundleDeliveryJob` exits immediately without re-delivering.
- *Error path:* `Aws::SES::Errors::MessageRejected` raised during `deliver_now` → bundle is `canceled_at`, error re-raised as `TerminalError`.
- *Error path:* Transient SES 5xx error during `deliver_now` → error propagates, `delivered_at` and `canceled_at` both nil, Solid Queue retries.
- *Integration:* On retry after a transient failure, the second `deliver_now` call passes the same idempotency key (stable across attempts).
- *Integration:* `bundle.items` is loaded with eager-loaded `message` and `actor` to avoid N+1 (verify with `assert_no_queries` or equivalent).

**Verification:**
- `bin/rails test test/jobs/notification/bundle_delivery_job_test.rb` green.
- All existing tests green.
- `SAAS=true bin/rails test saas/test/` is green — delivery job runs in carried tenant context.
- Manual smoke (with both flags on, in dev): create a bundle → wait for `ends_at` → observe email log line and `delivered_at` set; toggle user `missed_email_enabled` to false mid-window → observe `canceled_at` set on next delivery.

---

### Phase 5: Email surface

- U7. **`EmailUnsubscribable` concern + `MissedNotificationsMailer` + delivery-method idempotency-key passthrough + `EmailUnsubscribesController` + user settings UI**

**Goal:** Render the missed-notification bundle email, send it through the existing Resend/SES delivery methods with provider-side idempotency, and give users a way to unsubscribe and manage preferences.

**Requirements:** R7, R10, R11.

**Dependencies:** U6.

**Files:**
- Create: `app/mailers/concerns/email_unsubscribable.rb`
- Create: `app/mailers/missed_notifications_mailer.rb`
- Create: `app/views/missed_notifications_mailer/bundle.html.erb`
- Create: `app/views/missed_notifications_mailer/bundle.text.erb`
- Create: `app/controllers/email_unsubscribes_controller.rb`
- Create: `app/controllers/users/notification_settings_controller.rb`
- Create: `app/views/users/notification_settings/edit.html.erb`
- Modify: `config/routes.rb` (POST/GET unsubscribe routes; user notification settings resource)
- Modify: `config/initializers/email.rb` (`ResendDeliveryMethod` and `SesDeliveryMethod` extensions to read and consume `X-Idempotency-Key` header)
- Test: `test/mailers/missed_notifications_mailer_test.rb`
- Test: `test/mailers/concerns/email_unsubscribable_test.rb`
- Test: `test/controllers/email_unsubscribes_controller_test.rb`
- Test: `test/controllers/users/notification_settings_controller_test.rb`

**Approach:**
- `EmailUnsubscribable` concern (mailer-side):
  - `mint_unsubscribe_token(user, surface)` returns `Rails.application.message_verifier(:email_unsubscribe).generate({ user_id: user.id, tenant: ApplicationRecord.current_tenant, surface: surface })`. In self-hosted, `current_tenant` is `nil` and the controller's `with_tenant(nil)` is a no-op (arch § 9).
  - `unsubscribe_headers(user, surface)`: returns the RFC 8058 `List-Unsubscribe` and `List-Unsubscribe-Post` headers pointing at the `EmailUnsubscribesController` URL with the token.
  - `workspace_name`: reads `Account.sole.name` (runs inside the resolved tenant).
- `MissedNotificationsMailer#bundle(user, items)`:
  - Subject options per arch § 11 / prd § Email content: `"New mentions in #{workspace_name}"` if any items are mentions, else `"You have new messages in #{workspace_name}"`. Generic — no sender/room names in the subject (R11).
  - Body groups items by `item.message.room`, lists sender names + truncated previews using `Message#plain_text_body` (`app/models/message.rb:108-110`), primary CTA to Activity, secondary link to settings, unsubscribe link.
  - Sets `mail.headers["X-Idempotency-Key"] = "bundle-#{bundle.id}"` (the bundle is reachable via `items.first.bundle` — or pass `bundle` as a separate arg if cleaner).
  - Sets `mail.headers["List-Unsubscribe"]` and `List-Unsubscribe-Post` from the concern.
- Delivery-method extensions (`config/initializers/email.rb`):
  - `ResendDeliveryMethod#deliver!`: read `mail.header["X-Idempotency-Key"]&.value`, pass as `idempotency_key:` parameter to `Resend::Emails.send`. Strip the header from `params` so it's not duplicated as a body header.
  - `SesDeliveryMethod#deliver!`: read the same header, pass as `MessageDeduplicationId` (when configured for FIFO-style dedup) or via the SES configuration set's dedup window. The simplest v1 path is the SDK's `Aws::SESV2::Client#send_email` — verify whether the v2 SDK exposes a per-call dedup parameter and use that; otherwise document that the SES configuration set named in `SES_CONFIGURATION_SET` must be FIFO-configured. **Confirm in implementation; the architecture doc § 7.7 leaves the exact SES knob open.**
- `EmailUnsubscribesController`:
  - `GET /email/unsubscribe/:token` shows a confirmation page (RFC 8058 also requires a one-click POST endpoint for mail clients).
  - `POST /email/unsubscribe/:token` (one-click) decodes the token via `Rails.application.message_verifier(:email_unsubscribe).verify(token)`, enters the encoded tenant via `ApplicationRecord.with_tenant(payload[:tenant])`, and flips the appropriate column based on `payload[:surface]` (`:missed_notifications` → `missed_email_enabled: false`; `:weekly_digest` → `weekly_digest_subscribed: false`). Idempotent — re-clicking is fine.
  - Token verification rescues `ActiveSupport::MessageVerifier::InvalidSignature` and renders a generic "this link is no longer valid" page.
  - **Tenant-routing opt-out (SaaS).** The route does not carry a workspace path segment — the token is the tenant carrier (arch § 9). Sabha's `TenantSelector` resolver would otherwise reject the request as an unrecognized tenant. The controller wraps token verification in `ApplicationRecord.without_tenant { ... }` (gem § Active Record API) so message-verifier decode runs without a tenant context, then enters `with_tenant(payload[:tenant])` to flip the setting. The route is also configured to skip the `TenantSelector` middleware's "prohibits shard swapping" mode so the inner `with_tenant` is allowed to set the context (gem § 2.5 — "explicitly untenanted, we allow shard swapping"). Self-hosted has no resolver to skip; `payload[:tenant]` is `nil` and `with_tenant(nil)` is a no-op.

- **Mailer URL host split.** Two URL hosts are at play in one mailer:
  - **Activity link in body** (`room_path`, etc.) — per-tenant host. Per gem § ActionMailer, `config.action_mailer.default_url_options[:host]` uses `%{tenant}` interpolation in SaaS so workspace URLs resolve correctly. Self-hosted uses the single configured host.
  - **Unsubscribe link in body + `List-Unsubscribe` header** — global host. The token *is* the tenant carrier; this URL must not interpolate `%{tenant}`. Construct via an explicit `host:` argument to the URL helper inside `EmailUnsubscribable`, reading from a separate config (e.g. `Rails.configuration.x.unsubscribe_host`) that resolves to the bare app domain in SaaS and the configured host in self-hosted.
- **`Branding.mailer_from`** is expected to return a workspace-agnostic `From` address in SaaS (single shared sending domain per arch § 11.1). The bundle delivery job runs in tenant context, so a future tenant-dependent override would still resolve correctly — but v1 assumes a constant value.
- `Users::NotificationSettingsController`:
  - `GET /users/notification_settings/edit` renders a form with: master email toggle, frequency (hourly/daily), digest subscription, push toggle.
  - `PATCH /users/notification_settings` updates fields. Strong params permit only the four toggleable fields.
  - View follows the `app/views/users/push_subscriptions/index.html.erb` pattern.

**Execution note:** Test-first for the unsubscribe controller — the tenant-entry-from-token path is the security-sensitive piece. Other surfaces are conventional Rails work.

**Patterns to follow:**
- `app/mailers/user_mailer.rb` — mailer method shape, view template pairing.
- `app/views/user_mailer/email_verification.html.erb` — layout structure, link helper usage.
- `app/views/users/push_subscriptions/index.html.erb` — user-settings UI shape.
- `saas/app/models/workspace.rb:43-51` — `with_tenant` block shape.

**Test scenarios:**
- *Happy path:* `MissedNotificationsMailer#bundle(user, items)` renders both HTML and text parts, includes the workspace name in the subject, lists sender names + previews, has both CTA links.
- *Happy path:* The rendered mail has `X-Idempotency-Key: bundle-<id>` and the RFC 8058 `List-Unsubscribe` headers.
- *Happy path:* `ResendDeliveryMethod#deliver!` passes the header value as `idempotency_key:` to `Resend::Emails.send` (mocked). The header is removed from the outgoing API params so it's not double-sent.
- *Happy path:* `SesDeliveryMethod#deliver!` passes the header value to the SES API (mocked).
- *Happy path:* `POST /email/unsubscribe/:token` with a valid `:missed_notifications` token flips `user.notification_settings.missed_email_enabled` to false.
- *Happy path:* The `:weekly_digest` surface flips `weekly_digest_subscribed`, not `missed_email_enabled` (R10 — surface scoping).
- *Edge case:* Re-clicking unsubscribe is idempotent (no error, value stays false).
- *Edge case:* Subject contains no sender or room names even when the body does (R11).
- *Error path:* Invalid signature → controller renders a friendly 404-ish page, does not raise.
- *Error path:* Token from a different tenant → `with_tenant` enters the encoded tenant, finds the user there. (In SaaS, verify this against a two-tenant fixture: workspace A's token does not affect workspace B's settings.)
- *Integration:* Updating the user settings form sets the column; reload sees the new value.
- *Integration (SaaS-only):* The controller is reachable without path-based tenant routing; tenant comes from the token alone.

**Verification:**
- All mailer / controller tests green.
- Existing tests stay green.
- `bin/rails test` and `SAAS=true bin/rails test saas/test/` both green.
- Manual smoke (dev): trigger a bundle delivery → email arrives → click unsubscribe → user setting flips → next bundle for the same user is canceled (revalidation drops all items).

---

### Phase 6: Weekly digest

- U8. **`Notification::WeeklyDigestJob` + `WeeklyDigestMailer` + content selection + bundle GC**

**Goal:** Recurring weekly per-workspace job emails subscribed members (member opt-out model — `weekly_digest_subscribed: true` by default) a calm recap. Bundles older than 90 days are pruned at the top of each digest run.

**Requirements:** R4, R6, R10, R11.

**Dependencies:** U2, U3, U5, U6, U7.

**Files:**
- Create: `app/jobs/notification/weekly_digest_runner_job.rb` (untenanted fan-out)
- Create: `app/jobs/notification/weekly_digest_job.rb` (per-tenant work)
- Create: `app/mailers/weekly_digest_mailer.rb`
- Create: `app/views/weekly_digest_mailer/digest.html.erb`
- Create: `app/views/weekly_digest_mailer/digest.text.erb`
- Modify: `config/recurring.yml` (register the digest job, Tuesday 10:00 UTC)
- Modify: `app/views/accounts/_admin_settings.html.erb` (no change needed — admin flag was added in U3; a small caption clarifying when digests fire is a nice-to-have)
- Modify: `app/views/users/notification_settings/edit.html.erb` (digest subscription is wired in U7; verify the toggle exists)
- Test: `test/jobs/notification/weekly_digest_job_test.rb`
- Test: `test/mailers/weekly_digest_mailer_test.rb`

**Approach:**
- **Two-job fan-out, required by activerecord-tenanted.** A Solid Queue recurring task fires untenanted (the queue DB is global). `Notification::WeeklyDigestJob.perform_later` with no args at cron-fire time would have no tenant to enter and would raise `ActiveRecord::Tenanted::NoTenantError` on the first DB query. Split:
  - `Notification::WeeklyDigestRunnerJob#perform` (no args, registered as the recurring task in `config/recurring.yml`) iterates tenants via the gem-provided `ApplicationRecord.with_each_tenant` (gem § Active Record API): for each tenant, enqueue `Notification::WeeklyDigestJob.perform_later`. The enqueue happens *inside* `with_each_tenant`, so the gem's ActiveJob integration auto-carries that tenant on the serialized job (gem § Active Job).
  - `Notification::WeeklyDigestJob#perform` (no args, runs in the tenant carried from the runner) does the per-tenant work.
- `Notification::WeeklyDigestJob#perform`:
  - First, `Notification::Bundle.gc_terminal!` — pruner method that runs `Notification::Bundle.where("delivered_at IS NOT NULL OR canceled_at IS NOT NULL").where("updated_at < ?", 90.days.ago).delete_all` (arch § 7.6). Cascade via `dependent: :delete_all` on items. Tenant-scoped automatically.
  - If `Account.sole.weekly_digest_enabled? == false`, exit.
  - Otherwise, scope users: `User.joins(:notification_settings).where(user_notification_settings: { weekly_digest_subscribed: true }).verified.where(status: :active).where.not(role: :bot).where("user_notification_settings.last_digest_sent_at IS NULL OR user_notification_settings.last_digest_sent_at < ?", 6.days.ago)`.
  - For each, build content per arch § 8.3:
    1. `@everyone` mentions in the past week the member would have received an in-app row for, but did not view (joined to `notifications.user_id` and `notifications.activity_type = 'mention'`, filtered by `messages.mentions_everyone = true`, and `unread_at` semantics).
    2. Recently active accessible rooms (filter to non-DM, non-`invisible`, non-`nothing` memberships, `messages.created_at > 1.week.ago`, message count ≥ N — concrete N picked at implementation; start with 3).
    3. Excerpts: a small bounded number (start with 5) of recent message previews from those rooms.
  - If content is empty (no qualifying activity), skip without touching `last_digest_sent_at` (arch § 14.1).
  - Else send `WeeklyDigestMailer.digest(user, content).deliver_now`, then update `last_digest_sent_at`.
- `WeeklyDigestMailer#digest(user, content)`:
  - Subject: `"This week in #{workspace_name}"` (arch § 8.4).
  - Body: workspace name, recap section, recent excerpts (with `Message#plain_text_body` truncated), CTA to Activity, manage settings, unsubscribe.
  - `EmailUnsubscribable` concern: token surface is `:weekly_digest`. Independent unsubscribe scope (R10).
- `config/recurring.yml`:
  - Register `Notification::WeeklyDigestRunnerJob` (not `WeeklyDigestJob`) with `schedule: "0 10 * * 2"` (Tuesday 10:00 UTC). The runner is the untenanted entry point; per-tenant fan-out happens inside it. Confirm that Solid Queue's recurring tasks fire at the configured schedule in test/dev (test by running the runner manually with `bin/rails runner 'Notification::WeeklyDigestRunnerJob.perform_now'` first, then verify the recurring config triggers it on schedule).

**Execution note:** Test-first for content selection (the rules-not-algorithm shape is easy to get fuzzy without a pinned set of cases) and for the empty-skip vs. dedup behavior.

**Patterns to follow:**
- `app/jobs/create_thread_reply_notifications_job.rb` — job shape.
- `app/mailers/user_mailer.rb` — mailer method + view template pairing.
- `app/views/user_mailer/*.html.erb` — layout.

**Test scenarios:**
- *Happy path:* For a subscribed member with qualifying content, the job calls `WeeklyDigestMailer.digest` and sets `last_digest_sent_at`.
- *Happy path:* The job prunes terminal bundles older than 90 days (via the `delete_all` query at the top of each per-account run).
- *Happy path:* The mailer subject is `"This week in #{workspace_name}"`. No sender/room names in the subject (R11).
- *Edge case:* `account.weekly_digest_enabled: false` → no users emailed regardless of subscription state.
- *Edge case:* Subscribed user with `last_digest_sent_at` 3 days ago → skipped (dedup).
- *Edge case:* Subscribed user with no qualifying content → skipped, `last_digest_sent_at` is **not** updated (arch § 14.1).
- *Edge case:* Banned, deactivated, bot, or unverified user → skipped.
- *Edge case:* Active bundle older than 90 days is **not** pruned (only terminal bundles).
- *Integration:* Unsubscribe token from a digest email targets `:weekly_digest` surface; clicking it does not affect `missed_email_enabled`.
- *Integration (SaaS):* `WeeklyDigestRunnerJob#perform` enqueues exactly one `WeeklyDigestJob` per existing tenant via `with_each_tenant`. Each enqueued job carries its own tenant in serialized form.
- *Integration (SaaS):* The runner running with no tenants enqueues zero per-tenant jobs and exits cleanly.
- *Integration (SaaS):* A user subscribed in workspace A but not B receives a digest from A only — never B (tenant boundary inside the per-tenant `WeeklyDigestJob`).

**Verification:**
- `bin/rails test test/jobs/notification/weekly_digest_job_test.rb test/mailers/weekly_digest_mailer_test.rb test/jobs/notification/weekly_digest_runner_job_test.rb` green.
- All existing tests green.
- `SAAS=true bin/rails test saas/test/` is green — runner fan-out enqueues per-tenant jobs and tenant boundary holds.
- `config/recurring.yml` is loaded by Solid Queue; `bin/rails runner 'puts SolidQueue::RecurringTask.where(class_name: "Notification::WeeklyDigestRunnerJob").exists?'` returns true after a deploy.
- Manual smoke (dev): seed a user with subscription on, run the job once → email arrives, `last_digest_sent_at` set; rerun → user is skipped.

---

### Phase 7: Product integration and remaining coverage

- U9. **Notification preferences entry point + remaining SaaS/reliability tests**

**Goal:** Close the remaining integration gaps before rollout: make the preferences page discoverable inside the app, clarify how the new push preference relates to push device management, and add tests for the SaaS mail-link and digest failure-isolation behavior that already exists in code.

**Requirements:** R5, R7, R10, R12.

**Dependencies:** U7, U8.

**Files:**
- Remaining modify: `app/views/accounts/edit.html.erb` or the user profile/settings view that already acts as the user's account/preferences hub (add a visible link to notification preferences)
- Remaining modify: `app/views/users/notification_settings/edit.html.erb` (make the relationship to push device management explicit)
- Possible modify: `app/views/users/sidebars/show.html.erb` only if the sidebar is the established entry point for personal settings; do not create duplicate navigation if account/profile already covers it
- Test: `test/controllers/users/notification_settings_controller_test.rb` or an integration test covering the in-app link
- Test: `test/controllers/users/notification_settings_controller_test.rb` or a view/integration test covering the push-management link/copy
- Test: `test/mailers/missed_notifications_mailer_test.rb`
- Test: `test/mailers/weekly_digest_mailer_test.rb`
- Test: `test/jobs/notification/weekly_digest_job_test.rb`
- Test: SaaS-specific mailer/integration tests under `saas/test/` for workspace-prefixed links

**Approach:**
- **Add an in-app entry point.** The `Users::NotificationSettingsController` route is not enough by itself. Add a normal, discoverable link from the user's existing settings/profile/account surface to `edit_user_notification_settings_path(user_id: "me")`. The link text should match the page title ("Notification preferences") and should sit near existing profile/push/account controls. Email links are a secondary recovery path, not the primary navigation.
- **Resolve the push-settings overlap.** The new notification preferences page has a `push_enabled` checkbox, while `users/push_subscriptions#index` remains the device-management surface. Make the relationship explicit in UI: either link from notification preferences to the push subscription/device page, or keep device management on the existing page and label `push_enabled` as the global push switch. Do not leave users with two unrelated push settings pages that appear to conflict.
- **Add SaaS assertions for email links.** A SaaS test should render both missed-notification and weekly-digest emails inside a tenant and assert that Activity/settings links include `/1000001/...` while unsubscribe links do not. This is the regression test for the activerecord-tenanted guide's path-based routing nuance.
- **Add weekly digest failure-isolation coverage.** Add a focused job test proving a delivery failure for one eligible user does not block later eligible users.

**Execution note:** Treat this as the last gate before rollout. It is not optional polish: it covers discoverability, tenant correctness, and delivery semantics that users/admins will experience once flags are enabled.

**Patterns to follow:**
- `saas/app/mailers/workspace_mailer.rb` — explicit `script_name: workspace.slug` in path-based SaaS mailer links.
- `saas/lib/sabha/saas/path_rewriter.rb` — explains why workspace prefixes live in `SCRIPT_NAME`.
- `app/views/users/push_subscriptions/index.html.erb` — existing push-device management surface.
- `app/jobs/storage/reconcile_job.rb` and `app/jobs/room_update_broadcast_job.rb` — examples of explicit retry policy shape.

**Test scenarios:**
- *Happy path:* A signed-in user can reach Notification preferences from normal in-app navigation without coming from an email.
- *Happy path:* Notification preferences links to push device management, or clearly labels `push_enabled` as the global push switch.
- *Integration (SaaS, remaining test):* Missed-notification email Activity/settings links include the workspace path prefix.
- *Integration (SaaS, remaining test):* Weekly digest email Activity/settings links include the workspace path prefix.
- *Integration (SaaS):* Unsubscribe links remain global and still flip only the encoded tenant's settings.
- *Error path:* One weekly-digest recipient delivery failure does not prevent later eligible recipients from receiving the digest.

**Verification:**
- `bin/rails test test/controllers/users/notification_settings_controller_test.rb test/mailers/missed_notifications_mailer_test.rb test/mailers/weekly_digest_mailer_test.rb test/jobs/notification/weekly_digest_job_test.rb` green.
- `SAAS=true bin/rails test saas/test/` green, including explicit workspace-prefix assertions for notification email links.
- Manual smoke (dev): open the normal account/profile/settings UI, navigate to Notification preferences, toggle settings, return to push device management if needed.
- Manual smoke (SaaS dev): render both emails in tenant `1000001`, click Activity/settings links, and land inside `/1000001/...`; click unsubscribe and confirm the global token route still updates the tenant-scoped settings row.

---

## System-Wide Impact

- **Interaction graph (callbacks):** The new `dispatch_notifications` callback joins eight existing `after_create_commit` callbacks on `Message` and is order-sensitive (must run after `create_mention_notifications` and `create_thread_reply_notifications`). The dispatch contract test pins the order. Boost moves from inline to async dispatch — the existing `broadcast_notification_removal` on Boost destroy stays untouched.
- **Error propagation:** Dispatch job failures discard on `DeserializationError`. Bundle delivery rescues a documented set of terminal provider errors and sets `canceled_at` to break the partial-unique-index trap (arch § 14.1); commit `3593396` makes transient delivery retries explicit via `retry_on`. Weekly digest delivery isolates per-recipient failures so one bad address does not block the rest of the workspace. Nothing in the dispatch path can roll back the originating message create — all delivery work runs after the message is committed.
- **State lifecycle risks:** The bundle's `(user_id) WHERE delivered_at IS NULL AND canceled_at IS NULL` partial unique index is the load-bearing invariant. If a bundle gets stuck (terminal error not in the rescue list, or the rescue list misses a new provider error class), no further bundles are created for that user. Bundle GC does **not** mitigate this — only terminal bundles (`delivered_at IS NOT NULL OR canceled_at IS NOT NULL`) are pruned at 90 days; an actively-stuck active bundle is never deleted by GC. The single mitigation is the terminal-error rescue list (arch § 14.1), which must be comprehensive enough to catch any error that should terminate the bundle. See the corresponding risk-table row below.
- **API surface parity:** The plan does not change any external API (bot API, push subscription API, ActionCable channels). The Activity tab broadcast remains unchanged — `Notification` row creation still drives it. The `notification_recipient_ids` private method on `Message::Broadcasts` (touched by `test/models/message/broadcasts_test.rb`) is unrelated to the dispatch job and stays unchanged.
- **Integration coverage:** Cross-layer scenarios that mocks alone won't prove:
  - Callback ordering is integration-tested via the dispatch contract test (pinning behavior at the Rails callback chain level).
  - Multi-tenant unsubscribe from a token-only request requires a full SaaS test (in `saas/test/`) that crosses the controller, the verifier, and `with_tenant`.
  - SaaS notification email links require full mailer rendering under a tenant and assertions for `/workspace_id/...` path prefixes.
  - Bundle delivery's partial unique index race requires a full ActiveRecord transaction interleaving test, not just a mocked retry.
- **Unchanged invariants:**
  - `Notification.activity_type` enum stays `%w[mention boost thread_reply]` (R9, locked by `notification_dispatch_contract_test.rb`).
  - `Membership::Connectable::ACTIVITY_TIERS` constants are unchanged. Push still uses the 60-second `connected?` (arch § 4).
  - `Room::MessagePusher#build_payload` direct/shared two-branch shape is preserved verbatim (R8).
  - Existing `Notification` row creation paths for boost/mention/thread_reply produce the same rows; the dispatcher is a relocation, not a rewrite.
  - `users.preferences` JSON is **not** extended. Notification settings get a real table (arch § 6.4).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Callback ordering regression breaks the dispatcher | `test/models/notification_dispatch_contract_test.rb` pins the order. Any reorder fails CI loudly with a precise diff. |
| Recipient routing drifts during the `Room::MessagePusher` → `Message` move | `test/models/notification_routing_parity_test.rb` already locks recipients with exact-set assertions. Stays green at every commit in U4. |
| Bundle race-create produces two active bundles for one user | DB-enforced via partial unique index; `find_or_create_active_for` rescues `RecordNotUnique` and re-reads. Test simulates the race. |
| Bundle stuck after a terminal provider error not in the rescue list | The rescue list is documented at U6 with explicit class names per provider. New provider errors trigger a follow-up to expand the list. v1.1 webhook-driven suppression provides a richer signal stream but is out of scope. Active bundles are not GC'd, so stuck bundles persist — accepted in v1 and bounded by account-flag rollout gating. |
| SES `MessageDeduplicationId` plumbing turns out not to work without a FIFO configuration set | Tested at integration time. If the SDK's send_email doesn't expose a per-call dedup parameter, the operator-side requirement (configuration set named in `SES_CONFIGURATION_SET` must be FIFO-configured) is documented in the deploy runbook. Worst case, retries within the configuration set's dedup window do not duplicate; outside the window they could — bounded by Solid Queue's retry envelope (typically minutes, not hours). |
| Self-hosted operator turns the account flag on without configuring Resend domain | `email_notifications_enabled` defaults off; admin UI displays a setup-note caption. Resend itself rejects unverified-domain sends, which our terminal-error rescue catches and cancels the bundle. The user receives no email until the operator completes setup. |
| Backfill data migration takes too long on a large existing user base | `find_each` batches 1000 by default. For very large tenants (SaaS), an out-of-band backfill task may be safer than a deploy-time data migration. v1 plan accepts the in-line approach; if any tenant exceeds ~100k users we extract to a rake task. |
| Weekly digest content selection misfires on quiet workspaces (sends nothing) or noisy workspaces (sends too much) | "Skip on empty content" + "5 excerpts max" caps both directions. Tuning happens after first signal. |
| Multi-tenant leakage in unsubscribe controller | The token *is* the tenant carrier; controller test pins this in SaaS. Belt-and-suspenders: verify the decoded `user_id` exists in the entered tenant before flipping settings (a token leaked across tenants would resolve to a different user there, or not exist). |
| Solid Queue recurring task config doesn't trigger the digest in production | Verified at deploy by reading `SolidQueue::RecurringTask` after migration. Manual `perform_now` tested in dev. |
| Weekly digest fan-out misconfigured — `WeeklyDigestJob.perform_later` enqueued without a tenant context, raising `NoTenantError`, no tenant ever receives a digest | The plan splits runner (untenanted, registered) from digest (per-tenant, enqueued inside `with_each_tenant` so the gem auto-carries tenant). U8 has explicit fan-out tests. The recurring-task class name in `config/recurring.yml` is the runner, not the digest. |
| Unsubscribe controller route resolves to wrong tenant — leaks across workspaces | The token is the tenant carrier; controller wraps token decode in `without_tenant`, then `with_tenant(payload[:tenant])`. Route opts out of `TenantSelector`'s shard-swap prohibition (gem § 2.5). U7 has a SaaS test asserting workspace A's token does not flip workspace B's settings. |
| Notification preferences page exists but users cannot find it | U9 adds an in-app entry point from the existing personal settings/profile/account surface and tests the link. Email links are not treated as sufficient navigation. |
| SaaS email app links regress and lose the workspace prefix | U9 adds SaaS tests asserting `/1000001/...` links for Activity/settings while keeping unsubscribe global because the token carries tenant context. |
| Weekly-digest recipient failure isolation regresses | U9 adds a focused job test that later eligible users still receive a digest after one recipient delivery fails. |

---

## Documentation / Operational Notes

- **Admin runbook:** Add a section to `docs/multi-tenant/` (or wherever ops docs live) describing the v1 enablement path: verify Resend domain → flip `account.email_notifications_enabled` → monitor bounce rate / complaint rate via provider dashboard for 48 hours → flip `account.weekly_digest_enabled` if desired.
- **Self-hosted setup doc:** A short separate doc covers DKIM/SPF/DMARC + Resend domain verification. Out of plan scope but called out so it doesn't get forgotten.
- **Observability hooks:** The dispatch job and bundle delivery job emit Rails logger lines on each branch (delivered, canceled, terminal error). v1.1 may add a structured metrics layer; v1 logs are sufficient for hand investigation.
- **Migration order:** U2's two migrations (schema + backfill) ship in one PR. U3's migration ships in U3's PR. U5's two migrations ship in U5's PR. Do not run schema and backfill in separate deploys — the dispatcher's predicates assume settings exist.
- **Rollout sequencing:** All nine units land green before any account flag flips on. The flag flip is a separate operational step, not part of the implementation PRs.

---

## Sources & References

- **Origin (product):** [docs/plans/EMAIL-NOTIFICATIONS-PRD.md](EMAIL-NOTIFICATIONS-PRD.md)
- **Origin (architecture):** [docs/plans/NOTIFICATIONS-ARCHITECTURE.md](NOTIFICATIONS-ARCHITECTURE.md)
- **Competitive framing:** [docs/plans/NOTIFICATIONS-SLACK-COMPARISON.md](NOTIFICATIONS-SLACK-COMPARISON.md)
- **Superseded V0 reference:** [docs/plans/UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md](UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md). Kept for routing/eligibility background; do not implement from it.
- **Regression net:** `test/models/notification_routing_parity_test.rb`, `test/models/notification_dispatch_contract_test.rb`
- **Fizzy prior art (reference only):** `fizzy/app/models/notification/bundle.rb`, `fizzy/app/models/notification/pushable.rb`
- **Delivery wiring (existing):** `config/initializers/email.rb`
- **Solid Queue recurring schema:** `db/queue_schema.rb`
- **SaaS tenant entry pattern:** `saas/app/models/workspace.rb:43-51`
- **activerecord-tenanted gem guide:** [docs/multi-tenant/activerecord-tenanted-guide.md](../multi-tenant/activerecord-tenanted-guide.md). Load-bearing for U4 (Turbo broadcast scoping addendum), U7 (`without_tenant`/`with_tenant` in controller), and U8 (`with_each_tenant` fan-out).

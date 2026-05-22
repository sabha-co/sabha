# Foundation Refactor Plan

A pre-launch structural refactor of Sabha's models to make the codebase ready for Slack/Discord-scale feature expansion. Three slices: callbacks, User, and soft-deletion. Sequenced so each lowers the cost of the next.

## Status

- **Slice 1 (callbacks → concerns): shipped.** Message in [PR #80](https://github.com/sabha-co/sabha/pull/80); Room + Membership in [PR #81](https://github.com/sabha-co/sabha/pull/81).
- **Slice 2 (User decomposition): shipped in [PR #82](https://github.com/sabha-co/sabha/pull/82).** Seven concerns extracted; `User` shrank from 637 to 288 lines.
- **Slice 3 — reframed.** Originally planned as a Fizzy-style state-record refactor (`Message::Deletion` / `Room::Archive` / `Membership::Departure`). Direction dropped after audit: Fizzy is a productivity app with real workflow states; Sabha is a chat app where soft-delete is just a tombstone. No major chat app uses the state-record pattern. What actually shipped is a cleanup: dropped 9 redundant `.unscoped` calls across `user.rb` / `room.rb` / `rooms/thread.rb` and refreshed misleading comments. The `Deactivatable` concern stays. See the rewritten Slice 3 section below for details and what's been deferred.
- **Schema hygiene fallout from Slice 2:** [PR #83](https://github.com/sabha-co/sabha/pull/83) removed an orphan `users.accepted_terms_at` column from `db/schema.rb` that was crashing self-hosted signup but had gone unnoticed because fixtures bypass attribute-aware INSERTs. [PR #84](https://github.com/sabha-co/sabha/pull/84) re-synced missing `on_delete: :cascade` FK annotations. Both surfaced while exercising the User concern decomposition end-to-end in dev.

## Context

- **Sabha is pre-launch.** No production users. No data to migrate carefully. Breaking changes ship as fixes, not incidents.
- **Vision:** free SaaS chat at Discord scale; open-source self-hosted at single-tenant scale.
- **Two deployment modes share the same code.** Self-hosted is single-database (`db/migrate/`, `db/schema.rb`). SaaS runs `activerecord-tenanted` — every workspace gets its own SQLite at `storage/{env}/workspaces/{tenant_id}/main.sqlite3`. Untenanted globals (`GlobalIdentity`, `Workspace`, `WorkspaceMembership`, `GlobalSession`) live in PostgreSQL via `UntenantedRecord`. Models touched by this refactor — Message, Room, Membership, User — are all tenanted (`ApplicationRecord`).
- **Scope ahead:** feature parity with Slack/Discord — workflows, polls, scheduled messages, drafts, snippets, voice rooms, integrations, calendars, audit logs, retention policies, moderation tools, custom emoji, status/availability, do-not-disturb, saved items.

The question this plan answers: **what shape does the codebase need to be in before that scope lands?**

## Why now and not later

The cost of every foundation refactor is roughly constant. The cost of *not* doing them scales with the number of features built on top of the wrong foundation.

Three forces make pre-launch the cheapest moment:

1. **No backfill, no feature flags, no rollout.** Every refactor here would require feature-flagged dual-write paths in a live product. Pre-launch, the same change is a worktree branch and a test run.
2. **The boolean/God-object/inline-callback patterns compound per new model.** Every new feature stamped onto today's shape adds another deactivation field to remember in three places, another callback declared on a 200-line class, another method on a 600-line User. The boolean tax isn't paid once; it's paid every time you add a deletable thing.
3. **Reference codebases tell us the destination.** Once-campfire (Sabha's ancestor) and Fizzy (a more mature 37signals app on the same patterns) both ship the shape this plan moves toward. Fizzy's `Card` is 92 lines with 22 concerns. Sabha's `User` is 637 lines with 8.

## The three slices

### Slice 1 — Push callbacks into the concerns that own them ✅

**Shipped across [PR #80](https://github.com/sabha-co/sabha/pull/80) (Message) and [PR #81](https://github.com/sabha-co/sabha/pull/81) (Room + Membership).** Message dropped from 15 callbacks to 6 at the class level; Room and Membership each now declare ≤3.

**What.** A concern that adds behavior should own both the associations *and* the callbacks that trigger it.

**Reference shape (Fizzy):**
```ruby
module Card::Pinnable
  extend ActiveSupport::Concern

  included do
    has_one :pin, dependent: :destroy
    after_update_commit :broadcast_pin_updates, if: :preview_changed?
  end

  # method definitions
end
```

Fizzy `Card` ends up with 2 callbacks total at the class level. All other lifecycle logic lives in the concern that adds the feature.

**Why better as a foundation:**
- **New features bring their own callbacks.** A new `Card::Reactable` concern adds `has_many :reactions` *and* `after_create_commit :broadcast_reactions`. You don't reach into `Card` to register the callback. The concern is self-contained — drop it in, take it out.
- **Each feature's lifecycle is colocated.** Today, to understand "what happens when a Message is created," you read 15 callbacks on Message and chase 15 private methods. After: open `Message::Threadable` and see all five thread-related callbacks + handlers in one file.
- **Error boundaries align with features.** Rails wraps each callback declaration in its own error boundary. Failures in thread broadcasting don't break unread-counter logic when they're in different concerns.
- **Extracting a feature is mechanical.** If a feature gets cut, you delete the concern. Today, you'd have to grep the parent class for every callback and method that belonged to that feature.

**What landed in PR #81:**

| Model | Concerns introduced (or extended) |
|---|---|
| **Room** | `Room::Announceable` (creation broadcasts), `Room::Sortable` (sortable name + sidebar move broadcast), `Room::Restorable` (reactivation broadcast). `Room::Archivable` deferred to Slice 3. |
| **Membership** | `Membership::Cacheable` (member-count cache invalidation), `Membership::Connectable` (extended with `reset_user_connections_if_deactivated` + `reset_user_connections`), `Membership::Involvable` (involvement enum + broadcast), `Membership::Starrable` (star validation + dual-broadcast sidebar move) |

### Slice 2 — Decompose `User` into per-capability concerns ✅

**Shipped in [PR #82](https://github.com/sabha-co/sabha/pull/82).** Seven concerns extracted; `User` shrank from 637 to 288 lines (–55%).

**What.** Split the 637-line `User` model into 7 capability concerns. Each concern is the *whole* feature: associations, validations, callbacks, methods.

**Why better as a foundation:**
- **Feature flags via concern inclusion (or non-inclusion).** `User::Verifiable` either ships or doesn't. The self-hosted build and the SaaS build can include different subsets without scattering `if Sabha.saas?` across one file. (Exception: `User::SaasBridged` should include unconditionally with internal guards — see plan #7 details.)
- **Test surface localizes.** `user_test.rb` can split into `user/verifiable_test.rb`, `user/blockable_test.rb`, etc. Each concern's tests run independently and signal what broke without reading 800 lines of test setup.
- **New auth methods land as new concerns.** When SSO/SAML/OAuth-provider/passkey arrives, it's `User::SsoAuthable`, not 200 more lines stuffed into `user.rb`. Same for new notification channels (`User::PushNotifiable`, `User::SmsNotifiable`).
- **Reading is bounded.** Working on the password reset flow means opening `User::PasswordAuthable` and seeing the full picture. Today you read User top-to-bottom looking for password-related methods and have to mentally filter out everything else.

**What landed in PR #82:**

| Concern | What moved |
|---|---|
| `User::Streakable` | `current_streak` override, `recalculate_streak!`, `posted_on?` |
| `User::Blockable` | `blocks_given`/`blocks_received` associations, `block!`/`unblock!`/`blocked?`/`blocked_by?`/`blocked_in?`/`can_ping?`/`can_direct_message?`, `dm_room_with` |
| `User::PasswordAuthable` | `has_secure_password`, password length validation, the `password_reset` token, `send_password_reset_email` |
| `User::Verifiable` | `verified?`, `verify_email!`, `send_verification_email`, scopes, `email_verification` token, `after_create_commit :post_welcome_message` |
| `User::EmailChangeable` | full email-change flow, unconfirmed_email validation/normalize, `email_change` token, `email_changed` mailer callback |
| `User::Notifiable` | notifications/bundles/settings associations + callbacks, digest + bundle methods, `mark_inbox_as_read` flow, `touch_activity_seen_at`, `unseen_activity?`, `broadcast_activity_indicator` |
| `User::SaasBridged` | `workspace_membership` belongs_to + `global_identity` reader, `sync_workspace_membership_active`, `sync_name_to_global_identity`, `close_remote_connections` |

`User` is now the persistence shell + small core (name, role, status, identity).

**Protective coverage added before refactor:** 12 tests (8 self-hosted + 4 SaaS) closing pre-extraction gaps the audit surfaced — password-reset token rotation, bot-skip on the `email_changed` mailer, the `mark_inbox_as_read` stale-timestamp clamp, `close_remote_connections` SaaS-mode `current_tenant` scoping, and the `sync_name_to_global_identity` rescue contract.

**One callback-ordering shift to be aware of:** `after_create_commit` now fires in order `[ensure_notification_settings, post_welcome_message, grant_membership_to_open_rooms]` (previously `[ensure_notification_settings, grant_membership_to_open_rooms, post_welcome_message]`). Verified safe — `post_welcome_message` and `grant_membership_to_open_rooms` are functionally independent.

### Slice 3 — `Deactivatable` cleanup (not state records)

**Reframed.** The earlier draft of this slice called for replacing `active:boolean` with Fizzy-style state records (`Message::Deletion`, `Room::Archive`, `Membership::Departure`). After audit, that direction was rejected. Fizzy is a productivity app where cards have real workflow states the product talks about (open / closed / postponed / pinned). Sabha is a chat app where soft-delete is just a tombstone — "deleted message," "departed user," "archived room" are not workflow states the product surfaces. The structural shape doesn't translate.

**Industry references support keeping soft-delete:**

| Product | Messages | Membership | Channel/Room | Audit metadata |
|---|---|---|---|---|
| Slack | Soft (`deleted` flag) + tombstone | Soft (preserves prefs) | Soft (`is_archived`) | Separate audit-log service |
| Discord | Hard delete | Hard delete | Hard delete | Audit-log channel entries |
| Mattermost | `DeleteAt` timestamp + `Props.deleteBy` JSONB | Hard delete | `DeleteAt` timestamp | JSONB + generic `Audit` table |
| Zulip | Move to `ArchivedMessage` (grouped by `ArchiveTransaction`) | Soft (`active`), explicitly preserves prefs | `deactivated` boolean | `RealmAuditLog`: typed-FK event log with ~80 event types |
| once-campfire (Sabha's ancestor) | Hard delete | Hard delete | Hard delete | None |
| Sabha (today) | Soft (`active`) | Soft (`active`) | Soft (`active`) | None |

Sabha sits closest to Slack/Zulip. None of the four major chat apps use per-concept state records.

**Why the original Slice 3 was wrong:**

1. **The `destroy_all_associated_records` problem was misattributed.** `Deactivatable` adds two named scopes — not a `default_scope` — so `Message.where(creator_id: id)` already returns all rows including inactive ones. The defensive `.unscoped` calls were redundant, and the misleading comments above each method ("Why this exists instead of `dependent: :destroy`: associations have `-> { active }` scopes…") were not accurate. The 16-line `User#destroy_all_associated_records` exists for **FK-ordering** reasons (notifications before messages, bundle_items before bundles) and because most `has_many` declarations on `User` don't carry `dependent:`. Neither root cause is soft-delete.

2. **Hard-deleting `Membership` would silently regress preference preservation.** Today's soft-delete keeps `involvement` (notification preference: everything / mentions / nothing), sidebar starring, `unread_at`, and the presence-cache counters across leave-and-rejoin. Hard-delete plus a `Membership::Departure` carrying only `room_id` would reset all of them on re-join. Zulip explicitly preserves Subscription rows for exactly this reason: *"we mark Subscription objects as inactive, rather than deleting them, when a user unsubscribes, so we can preserve user customizations like notification settings, stream color, etc."* The state-record plan would have inverted Sabha's UX without flagging it.

3. **State records add JOIN cost to the hottest read path.** Loading the last N messages in a room is Sabha's single most-frequent query. State records make it a LEFT JOIN against `message_deletions` filtered through `where.missing(:deletion)`. Soft-delete columns are a single indexed `WHERE active = true`. For productivity apps where most cards reach a terminal state, the JOIN cost amortizes. For chat where <1% of messages are ever deleted, the JOIN is pure overhead on every read.

4. **The audit-metadata argument doesn't require per-concept state records.** Zulip's `RealmAuditLog` covers ~80 event types — deletion, role changes, permission edits, settings updates — in one typed-FK table. Sabha will eventually want something similar for moderation/compliance. Per-concept state records (`Message::Deletion` etc.) don't replace that need; they live alongside it. So adding three state-record tables doesn't prevent the eventual generic audit log; it just adds three tables to maintain in addition.

**What actually shipped — [PR #85](https://github.com/sabha-co/sabha/pull/85)** (branch `prune-redundant-destroy-cleanup`, two commits):

1. **Dropped 9 redundant `.unscoped` calls** across `app/models/user.rb`, `app/models/room.rb`, `app/models/rooms/thread.rb`, and refreshed the misleading docstring on `Deactivatable` plus the misleading lead comments on the `destroy_all_associated_records` methods.
2. **Dropped 7 manual cleanup statements** from `User#destroy_all_associated_records` that were duplicating work `dependent: :destroy` / `:delete_all` declarations were already doing on `sessions`, `auth_tokens`, `searches`, `push_subscriptions`, `notification_settings`, and the two `blocks_*` associations. Remaining explicit statements carry inline comments noting why they're intentionally NOT delegated to Rails (Search second-FK, Ban `bust_cache` skip, Bundle bulk-delete perf).

Pure cleanup, zero behavior change. Confirmed safe in both deployment modes: `activerecord-tenanted` uses **connection switching** (`with_tenant` / `current_tenant`) for tenant isolation, not query scopes — `.unscoped` doesn't affect tenant boundaries. The method shrinks from 18 statements to 11, with the remaining 11 each doing real, non-`dependent:`-substitutable work.

**Deferred items (intentionally, not in this plan):**

- **Audit metadata.** When the first moderation feature lands and needs "who deleted this message" / "who kicked this member" / "who archived this channel," add either:
  - *Inline:* columns on the existing tables (`messages.deleted_at`, `messages.deleted_by_id`, `messages.deletion_reason`, ditto for rooms and memberships). Mattermost-shaped. One migration per model, no new tables, no JOIN cost.
  - *Generic:* one `audit_logs` table with typed FKs and an event-type enum (Zulip's `RealmAuditLog` shape). Useful for non-deletion events too.

  Pick the shape when product asks; don't pre-build.

- **FK-cascade tightening.** Most `has_many` declarations on `User` lack `dependent:`. Adding `dependent: :destroy` / `dependent: :delete_all` where appropriate would shrink `User#destroy_all_associated_records` substantially. Orthogonal to soft-delete; do as a standalone PR next time you touch User associations or notice a missed cleanup.

- **`docs/ARCHITECTURE.md` references.** AD #4 ("Soft deletion is first-class"), the Key Conventions soft-deletion bullet, and the Model Organization table row still describe `Deactivatable` in language that pre-dates this clarification. Update at convenience — not blocking.

## Soft-delete inventory

Documenting where soft-delete is applied today, since the pattern is staying. Useful as a reference when adding new models or auditing whether a new feature needs deactivation semantics.

**Includes `Deactivatable` (boolean `active` column):**
- `Message` — `messages.active` (default `true`). Read scope `Message.active`. Indexed via `(active, room_id, created_at)`.
- `Room` (STI base — covers `Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`, `Rooms::Thread`) — `rooms.active`. STI subclasses share the column.
- `Membership` — `memberships.active`. Carries per-membership preferences (involvement, starring, `unread_at`, presence counters) — soft-delete preserves these across leave-and-rejoin.

**Different pattern (already correct):**
- `User` — uses `enum :status, %i[active deactivated banned]`, not `Deactivatable`. The pattern from once-campfire; preserves the row, scrubs nothing.

**Hard-deleted (no change needed):**
- `Boost`, `Bookmark`, `Mention` — `dependent: :destroy` / `dependent: :delete_all`. Already correct.
- `Account`, `Session`, `AuthToken`, `Push::Subscription`, `Webhook`, `Badge`, `Search`, `Ban`, `Block` — none use `Deactivatable`. No change.

**SaaS-only mirror (untenanted):**
- `workspace_memberships.user_active` — a denormalized boolean that mirrors `users.status == :active`. Not soft-delete for `WorkspaceMembership` itself; it's a cache kept in sync by `User::SaasBridged#sync_workspace_membership_active`. Only writer remains the `User#status` callback — see multi-tenant point #8.

**Vestigial (worth cleaning up in a separate hygiene PR):**
- `accounts.active` — column exists in `db/schema.rb` but the `Account` model doesn't reference it and no caller reads or writes it. Dead schema, not in scope here.

**No follow-up needed under the new direction:**
- FTS5 search index (`Message::Searchable`) keeps the existing `where(active: true)` filter — no migration to chase.
- `RemoveBannedContentJob` keeps flipping `active: false` — no record-creation refactor.
- `Message.insert!` system-event bypass stays exactly as it is — was always orthogonal to soft-delete anyway.

## Multi-tenant considerations

Sabha runs in two modes from one codebase, with the SaaS mode using `activerecord-tenanted`. Every slice in this plan must work cleanly in both. Constraints that fall out of the tenanting model:

1. **All three state records (`Message::Deletion`, `Room::Archive`, `Membership::Departure`) inherit from `ApplicationRecord` — i.e., they are tenanted.** They live alongside their parent tables in each workspace's SQLite database. Migrations go in `db/migrate/` (the tenanted set), schema in `db/schema.rb`. No untenanted state records in this refactor.

2. **Adding tenanted tables means migrating every existing workspace database.** `bin/rails db:migrate:primary` walks all tenants. `SAAS=true bin/rails db:migrate:primary` chains untenanted + tenanted. The pre-launch context makes this trivial (no real tenants yet), but the same migration must work cleanly when there are 100 workspaces — i.e., the migration must be additive and reversible per-tenant.

3. **GlobalIDs in broadcasts auto-include the tenant.** When `Message::Deletion#after_create_commit` broadcasts a Turbo stream change, `to_global_id` on the tenanted parent record already embeds `?tenant=`. **But bare-symbol streams (`broadcast_replace_to :inbox`) do NOT — they collide across tenants.** All broadcasts moved into concerns by Slice 1 must take a tenanted model as the first argument: `broadcast_replace_to room, :messages` (good) — never `broadcast_replace_to :messages` (cross-tenant collision in SaaS).

4. **`User::SaasBridged` (Slice 2) is the home for tenant-bridge callbacks.** ✅ Done in PR #82. `sync_workspace_membership_active` (syncs status changes to the *untenanted* `WorkspaceMembership` table) and `sync_name_to_global_identity` both moved into `app/models/user/saas_bridged.rb` and keep their internal `Sabha.saas?` guards — included unconditionally, no-op in self-hosted. The contract is pinned by `saas/test/models/user/saas_bridged_test.rb`.

5. **Active Job + tenanted records.** Background jobs triggered by Slice 3 callbacks (e.g., counter rebalancing on a deletion's `after_create_commit`) inherit the current tenant context automatically when enqueued, and the tenanted GlobalID locator picks the right tenant DB on perform. No special handling needed — just don't introduce raw tenant arguments to jobs that could be set wrong.

6. **Test matrix is non-negotiable.** Every PR in this plan must pass both:
   - `bin/rails test` (self-hosted)
   - `UNTENANTED_DATABASE_URL= SAAS=true bin/rails test saas/test/` plus `SAAS=true bin/rails test` (SaaS)
   A pattern that works in self-hosted but breaks tenanted broadcasts in SaaS is a regression even if CI is green for one mode.

7. **Schema cache dumps.** The tenanting gem uses `use_schema_cache_dump = true` with `check_schema_cache_dump_version = false`. After adding any tenanted table, regenerate the schema cache dump (`bin/rails db:schema:cache:dump`) and commit it. Skipping this works locally but breaks production cold starts.

8. **Reactivation paths cross the tenant/untenanted boundary — keep the two flows independent.** "Reactivation" is overloaded; this contract holds today and shouldn't drift.

   - **Two distinct flows:**
     - **User reactivation** (`User#reactivate`) — flips `users.status` from `:deactivated` back to `:active`, then walks the user's inactive memberships and flips them back. The `User::SaasBridged#sync_workspace_membership_active` callback mirrors the status change to the untenanted `WorkspaceMembership.user_active`. This is the *only* path that touches the untenanted mirror.
     - **Membership reactivation** — flipping `memberships.active` back to `true` for one room. Purely tenanted; the untenanted mirror is not involved.
   - **Don't wire untenanted-mirror writers onto `Membership` lifecycle hooks.** The mirror is keyed to *account* state, not *room membership* state — conflating them produces phantom workspace re-admits when a user re-joins a single room.
   - **No new `WorkspaceMembership.user_active` writers anywhere.** The only writer remains `User::SaasBridged#sync_workspace_membership_active`, triggered by `User#status` changes. Enforce by code review.
   - This was originally written for the state-record direction (when reactivation meant destroying a `Membership::Departure` row). Same contract, same boundary, different mechanism. Kept here because the principle outlives the implementation choice.

## Execution order

Sequenced so each slice lowers the cost of the next:

1. ✅ **Slice 1 — Message + Room + Membership callbacks into concerns** — *Shipped in PR #80 and PR #81.*
2. ✅ **Slice 2 — User decomposition** — *Shipped in PR #82.*
3. ✅ **Slice 3 — `Deactivatable` cleanup (reframed)** — *Shipped in [PR #85](https://github.com/sabha-co/sabha/pull/85).* The originally-planned state-record refactor was rejected; what shipped is a two-commit cleanup that dropped 9 redundant `.unscoped` calls, 7 manual cleanup statements covered by existing `dependent:` declarations, and refreshed three misleading docstrings/comments. See the Slice 3 section above for the audit and the deferred follow-ups.

The plan is effectively complete. Every feature shipped onto today's foundation now has the concern-decomposed shape — adding a moderation/audit/retention feature lands as a new concern on the relevant model. Soft-delete stays as the underlying pattern, matching how every major chat app handles it.

## What we are not doing

- **No service-layer extraction.** Keep logic on models. Once-campfire refuses `app/services/`; Sabha follows.
- **No policy gem, no form objects.** Authorization stays model-level; forms stay views + strong params.
- **No state-record refactor.** `Message::Deletion` / `Room::Archive` / `Membership::Departure` were proposed and rejected. Soft-delete stays. See the Slice 3 reframing for the audit.
- **No premature shared concerns.** No `StateDeactivatable`, no generic `Auditable`. When audit metadata is needed, pick the cheapest shape for the actual product ask (columns on the existing table, or one generic `AuditLog`).
- **No backwards-compatibility shims.** Pre-launch — change the API, update the callers, move on.

## Definition of done

The foundation refactor is complete when:

1. ✅ `Room` and `Membership` declare ≤3 callbacks each at the class level. *(Shipped in PR #81.)*
2. ✅ `User` shrunk substantially; remaining logic lives in capability concerns. *(Shipped in PR #82 — 637 → 288 lines, –55%. The earlier ≤200 target was aspirational; 288 is the actual landing point and further reduction is left to future per-feature concerns.)*
3. ✅ `Deactivatable` documentation no longer misleads. The docstring describes what the concern actually does; `destroy_all_associated_records` lead comments accurately attribute the methods' existence to FK ordering + missing `dependent:` declarations, not soft-delete. *(Shipped in [PR #85](https://github.com/sabha-co/sabha/pull/85).)*
4. ✅ Redundant `.unscoped` calls removed. `grep '.unscoped' app/` returns zero hits. *(Shipped in [PR #85](https://github.com/sabha-co/sabha/pull/85).)*
5. ✅ Manual cleanup duplicating existing `dependent:` cascades removed. 7 statements pruned from `User#destroy_all_associated_records`. *(Shipped in [PR #85](https://github.com/sabha-co/sabha/pull/85).)*
6. Every test suite passes both modes:
   - `bin/rails test`
   - `UNTENANTED_DATABASE_URL= SAAS=true bin/rails test` and `SAAS=true bin/rails test saas/test/`

Out of scope (deferred to product-driven follow-ups, not blocking the foundation):
- Audit-metadata schema for moderation features.
- FK-cascade tightening on `User` associations.
- `docs/ARCHITECTURE.md` AD #4 / Key Conventions / Model Organization refresh to align language with the cleanup.

## References

- **Completed work this plan delivered:**
  - [PR #79](https://github.com/sabha-co/sabha/pull/79) — quick wins #1–#5 (precursor)
  - [PR #80](https://github.com/sabha-co/sabha/pull/80) — Message callback decomposition (Slice 1)
  - [PR #81](https://github.com/sabha-co/sabha/pull/81) — Room + Membership callback decomposition (Slice 1)
  - [PR #82](https://github.com/sabha-co/sabha/pull/82) — User decomposition (Slice 2)
  - [PR #83](https://github.com/sabha-co/sabha/pull/83) — schema hotfix: drop orphan `users.accepted_terms_at`
  - [PR #84](https://github.com/sabha-co/sabha/pull/84) — schema hotfix: re-sync FK `on_delete: :cascade` annotations
  - [PR #85](https://github.com/sabha-co/sabha/pull/85) — Slice 3 cleanup (redundant `.unscoped` removal, manual cleanup pruning, docstring refresh)
- **Companion doc:** `docs/plans/DHH-RAILS-STYLE-REFACTOR.md` — the original style-review findings this plan derives from. Section 8 was originally the state-record plan and has been rewritten to match the new direction.
- **Industry references consulted during the Slice 3 audit:**
  - Slack (public docs on soft-delete + audit log service)
  - Discord (public docs on hard-delete + audit log channels)
  - Mattermost: <https://github.com/mattermost/mattermost> (`server/public/model/post.go`, `channel.go`, `channel_member.go`, `user.go`, `audit.go`)
  - Zulip: <https://github.com/zulip/zulip> (`zerver/models/messages.py` — `ArchivedMessage` / `ArchiveTransaction`; `streams.py` — `Subscription`; `realm_audit_logs.py`)
- **Reference codebases:**
  - once-campfire: `/Users/ashwin/dev/once-campfire` — Sabha's direct ancestor; hard-deletes throughout. The pattern Sabha came from.
  - Fizzy: `/Users/ashwin/dev/fizzy` — referenced for Slice 1 / Slice 2 patterns (concern decomposition); explicitly *not* used as the model for Slice 3 (productivity app, different state semantics — see Slice 3 audit).
  - 37signals style guide: `/Users/ashwin/dev/unofficial-37signals-coding-style-guide`

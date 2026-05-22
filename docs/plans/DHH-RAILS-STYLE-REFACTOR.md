# DHH/37signals Style Refactor Plan

Findings from a style review of `app/` against once-campfire (the direct ancestor) and Fizzy (a more mature 37signals codebase). Items are ordered roughly by leverage-to-effort. Each item names the reference codebase pattern that justifies the change.

## Background

Sabha forked from Campfire and inherits most of its conventions verbatim. Where Sabha diverges from Campfire **and** Fizzy points at a sharper version of the same pattern, it's worth a refactor. Where Sabha matches Campfire literally (even if it looks unusual), it's the house style — leave alone.

This doc only lists divergences worth acting on. Things Sabha got right (REST decomposition into nested singular resources, `Current` attributes, model-level authorization, Hotwire/Turbo, Solid Queue, importmap/propshaft, broadcasting from controllers) are not catalogued here.

## Status

- **Quick wins #1–#5: shipped in [PR #79](https://github.com/sabha-co/sabha/pull/79).** Kept below as a reference for future similar cleanups.
- **Structural refactors #6–#7: not started.**
- **Architectural spike #8 (`Deactivatable`): not started; treat as a separate project.**

## Quick wins (shipped — PR #79)

### 1. Delete `app/services/`; move `SlackImporter` under a model namespace ✅

Neither once-campfire nor Fizzy has an `app/services/` directory. Fizzy keeps similarly complex flows (`Export`, `Signup`) at the top of the models tree or under model namespaces. A single occupant establishes the directory as a precedent without justifying it.

**Shipped:** Moved `app/services/slack_importer.rb` → `lib/slack/importer.rb` as `Slack::Importer`, next to its existing `Slack::UsersImporter` / `Slack::ImportContext` collaborators rather than under `app/models/` (the namespace was already established in `lib/`). `app/services/` deleted.

### 2. Fix `Users::ProfilesController#update` (and siblings) to handle validation failure ✅

Sabha copied a Campfire idiom that ignores `@user.update`'s return value and always redirects with a success notice. **Fizzy demonstrates the right version.**

**Reference — `fizzy/app/controllers/users_controller.rb`:**
```ruby
def update
  if @user.update(user_params)
    redirect_to @user
  else
    render :edit, status: :unprocessable_entity
  end
end
```

**Sites to fix:**
- `app/controllers/users/profiles_controller.rb:11` and `:34`
- `app/controllers/accounts/users_controller.rb:24`
- Audit any other `\.update\(` in controllers without a return-value check.

Non-bang `.update` is fine (Fizzy uses it); silently ignoring the return value is the bug.

### 3. Align `MessagesController#create` with the once-campfire canonical version

**Reference — `once-campfire/app/controllers/messages_controller.rb`:**
```ruby
def create
  set_room
  @message = @room.messages.create_with_attachment!(message_params)

  @message.broadcast_create
  deliver_webhooks_to_bots
rescue ActiveRecord::RecordNotFound
  render action: :room_not_found
end
```

**Sabha changes:**
- Switch `create_with_attachment` → `create_with_attachment!` and rescue `ActiveRecord::RecordInvalid` instead of branching on `@message.persisted?`.
- The rescue **must still `render action: :not_allowed`** — that template is the deliberate composer-error UI for `ensure_can_message_recipient` and `ensure_everyone_mention_allowed` failures. The refactor swaps the *trigger* (return value → exception); it doesn't change the response. Don't accidentally turn validation failures into 500s or a different Turbo response.
- Keep the controller-driven `broadcast_create` / `broadcast_mentionee_sidebar_updates` / `notify_bots` calls — broadcasting from controllers **is** the Campfire convention.

### 4. Scope all controller lookups through `Current.user.<accessible_*>`

Most of Sabha already does this (`Current.user.reachable_messages.find(...)`). The one outlier is `Rooms::MembershipsController#set_joinable_room`:

```ruby
@room = Room.active.find(params[:room_id])
head(:forbidden) and return unless @room.open?
```

Fizzy and Campfire both fetch through the user (`Current.user.boards.find`, `Current.user.rooms.find_by`). The 403 falls out of `ActiveRecord::RecordNotFound`.

**Definition matters here:** "joinable rooms" is not `Current.user.rooms.open` — that only includes rooms the user is already a *visible* member of. Joinability also has to cover the **re-join** case: a user with an inactive or invisible membership in an open room should still be able to POST to `/rooms/:id/membership`. Define joinable as **"active rooms of type `Rooms::Open`, regardless of the user's membership state"**, and let `Room#accept_join!` do the find-or-restore-or-create dance via `memberships.grant_to`.

In practice this is `Rooms::Open.active.find(params[:room_id])` — broader than `Current.user.rooms` because joinability doesn't depend on user identity beyond authentication. If a stricter "exclude users who already have an active visible membership" feels needed, prefer adding it on top via `Rooms::Open.browsable_by(Current.user)` (which already exists) rather than narrowing the join scope itself.

### 5. Reuse the `Sidebar` concern's `broadcast_sidebar_room_removed` instead of inlining the loop

once-campfire's version is one line. Sabha's `RoomsController#broadcast_remove_room` (and the duplicate copy in `api/bots/rooms_controller.rb`) iterates `Sidebar::SIDEBAR_SECTIONS` and calls `helpers.dom_prefix` from the controller — that's view/sidebar internals leaking into the controller, and it's duplicated.

**Action:** The `Sidebar` controller concern already exposes `broadcast_sidebar_room_removed(streamable, room)` for the per-user case. Generalize the first arg from `user` to `streamable` and call it from both `RoomsController` and `API::Bots::RoomsController` with `Current.account`. The room model doesn't need to know about sidebar list names; the concern is the right host because it already owns `SIDEBAR_SECTIONS` and `dom_prefix` access.

## Structural refactors

### 6. Push callbacks and their handlers down into the concern that owns the behavior

**The single biggest divergence from Fizzy.**

Fizzy's rule: a concern that adds behavior owns both the associations *and* the callbacks that trigger it. Example from `fizzy/app/models/card/pinnable.rb`:

```ruby
module Card::Pinnable
  extend ActiveSupport::Concern

  included do
    has_one :pin, dependent: :destroy
    after_update_commit :broadcast_pin_updates, if: :preview_changed?
  end

  # ... method definitions ...
end
```

`Card` itself ends up with 2 callbacks. Fizzy Card with 22 concerns has 8 callbacks total across all of them.

Sabha Message currently has **15 callbacks declared in the parent class**, with the handler methods also defined in `Message` (private). That's the structural bug.

**Decomposition plan for Message:**

| Move to concern | Callbacks |
|---|---|
| `Message::Mentionee` (exists) | `:create_mention_notifications`, `:destroy_stale_mention_notifications` |
| `Message::Threadable` (new) | `:involve_creator_in_thread`, `:update_thread_reply_count`, `:update_parent_message_threads`, `:create_thread_reply_notifications`, `:broadcast_parent_message_to_threads` |
| `Message::Unreadable` (new) | `:increment_unread_notifications_counters`, `:clear_unread_timestamps_if_deactivated`, `:restore_unread_notifications_counters_if_reactivated`, `:destroy_notifications_if_deactivated` |
| `Message::Streakable` (new) | `:update_creator_streak` |
| Stays on `Message` | `:set_default_client_message_id`, `:touch_room_activity`, `:deliver_to_room`, `:dispatch_notifications`, `:broadcast_reactivation_if_restored` |

Apply the same audit to:
- **Room:** `:broadcast_reactivation_if_restored`, `:announce_creation`, `:broadcast_updates`, plus `deactivate` / `reactivate` / `destroy_all_associated_records` → consider `Room::Deactivatable` (Sabha-specific, not the generic concern) that owns lifecycle + the callbacks that fire on it.
- **Membership:** `:reset_user_connections_if_deactivated`, `:reset_user_connections`, `:invalidate_room_member_count_cache`, `:broadcast_involvement`, `:broadcast_star_change` → distribute to `Connectable`, `Notifiable`, or new `Starrable`.

### 7. Decompose `User` (637 lines) into more concerns

Fizzy Card is 92 lines + 22 concerns. Sabha's User has 8 concerns and 600+ lines of inline behavior. Targets:

| New concern | What moves |
|---|---|
| `User::Verifiable` | `verified?`, `verify_email!`, `send_verification_email`, `generates_token_for :email_verification` |
| `User::EmailChangeable` | `update_email`, `confirm_email_change!`, `cancel_email_change!`, `pending_email_change?`, `send_email_reconfirmation`, `send_email_change_notification`, `generates_token_for :email_change` |
| `User::Streakable` | `current_streak`, `recalculate_streak!`, `posted_on?` |
| `User::Blockable` | `blocked_in?`, `can_ping?`, `blocked?`, `blocked_by?`, `block!`, `unblock!`, the `blocks_given`/`blocks_received` associations |
| `User::PasswordAuthable` | `has_secure_password`, password validation, `send_password_reset_email`, `generates_token_for :password_reset` |
| `User::Notifiable` | `unsubscribe_from_email!`, `deliver_weekly_digest_now`, `active_notification_bundle`, `open_notification_bundle!` |
| `User::SaasBridged` | `global_identity`, `sync_workspace_membership_active`, `sync_name_to_global_identity` |

**`User::SaasBridged` should be `include`d unconditionally**, with each method guarding internally on `Sabha.saas?` (and short-circuiting in single-tenant mode). Don't `include` it conditionally — that makes the model's shape vary by deployment, which breaks tooling that introspects the class (test helpers, fixtures, schema cache invalidation) and means a method that works in CI may not exist in production or vice versa. The pattern matches how `Current#workspace`/`#account` already guard internally on `Sabha.saas?`.

`User` becomes the persistence shell + the small handful of methods that don't fit any one bucket.

## Architectural spike (separate track)

### 8. Replace `Deactivatable` soft-delete with hard-delete + state records (Fizzy way) or `enum :status` (Campfire way)

> **Not a style refactor — treat as an architectural spike.** This is a data-model change with high blast radius: tests around reactivation, unread counters, room deletion, membership visibility, broadcasting, and the SaaS workspace lifecycle all depend on the current semantics. Don't mentally bundle this with the quick-win style cleanups. Plan it as a discrete project, with a design doc, a feature-flagged rollout, and a single model migrated at a time.

`Deactivatable` (boolean `active` column + scope + manual `destroy_all_associated_records`) is **not** Campfire heritage — it came from the Small Bets fork. once-campfire uses `dependent: :destroy` on Room and Message (hard delete). once-campfire User uses `enum :status, %i[ active deactivated banned ]` — which Sabha already does for User.

Costs Sabha pays for the current pattern:
- `User#destroy_all_associated_records` has 15 explicit `delete_all` calls because `dependent: :destroy` misses `active: false` rows.
- `Room#destroy_all_associated_records` and `Message#destroy_all_associated_records` exist for the same reason.
- `rewhere(active: false)` needed in reactivation paths.
- `Room#post_system_message` uses `Message.insert!` to bypass callbacks, then re-fetches — partially because the soft-delete model means callbacks fire in contexts they shouldn't.
- New deletable models require remembering to update three `destroy_all_associated_records` methods.

**Two options:**

**(a) Hard delete + state record (Fizzy convention).** Drop the `active` column. Add `Message::Deactivation`, `Room::Deactivation`, `Membership::Deactivation` records (creator, created_at, reason). Scopes become joins:
```ruby
Message.joins(:deactivation)         # deactivated
Message.where.missing(:deactivation) # active
```
Reactivation = `deactivation.destroy`. Hard delete = `message.destroy` (and the deactivation cascades via `dependent: :destroy`).

**(b) `enum :status` (Campfire User convention).** Add `status` column with `%i[ active deactivated ]`. Scopes become `where(status: :active)`. Less rich than (a) — no who/when/why — but a smaller migration.

**Recommendation:** **Don't propagate `Deactivatable` to new models** starting now. Pick (a) or (b) for an existing model when you next touch one of {Message, Room, Membership}; do them one at a time, behind a feature flag if needed. Don't migrate all three in one PR.

## Don't act on these (false positives from the initial review)

These were flagged in the first pass but are actually Campfire idioms. Documenting them so future reviews don't re-raise:

- **`delete :clear, on: :collection` on `searches`** — once-campfire routes do exactly this.
- **`get "webmanifest" => "pwa#manifest"` / `get "service-worker" => "pwa#service_worker"`** — verbatim in once-campfire/config/routes.rb.
- **`set_room` redirecting inside the setter** — once-campfire/app/controllers/rooms_controller.rb uses the same pattern.
- **Broadcasting from controllers (`@message.broadcast_create` in `MessagesController#create`)** — once-campfire/app/controllers/messages_controller.rb does this on purpose. Controllers decide *when* to broadcast; models decide *how* (via `room.receive`).
- **Small `Authorization` controller concern (10 lines)** — once-campfire's is comparable. Concerns don't need to be big.
- **Soft-delete predicates like `deactivated?`** — fine as a model-API surface; the issue is the *implementation* (boolean column + manual cleanup), not the predicate names.
- **`User#status` enum** — matches once-campfire exactly. Don't conflate this with the `Deactivatable` boolean.

## Suggested execution order

Each item is independent unless noted.

1. Quick wins #1–#5. Small PRs, each <100 LOC change. Land within a week.
2. Concern-callback decomposition for Message (#6, Message slice only). One PR, well-tested.
3. Same decomposition for Room and Membership (#6, remaining slices).
4. User decomposition (#7). Can be split into one PR per new concern.

**Separate track (not part of the style cleanup):** the `Deactivatable` migration in #8. Treat this as a standalone architectural project with its own design doc and feature-flagged rollout. Pick the lowest-blast-radius model (probably Membership) for a spike before committing to the rest.

## References

- once-campfire: `/Users/ashwin/dev/once-campfire`
- Fizzy: `/Users/ashwin/dev/fizzy`
- 37signals style guide: `/Users/ashwin/dev/unofficial-37signals-coding-style-guide`

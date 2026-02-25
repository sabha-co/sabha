# Sabha Code Review & Audit Report

**Date:** February 10, 2026
**Scope:** Full codebase review across security, architecture, performance, frontend, and data integrity
**Method:** 5 specialized review agents working in parallel

---

## Executive Summary

Sabha is a well-structured Rails chat application with solid architectural foundations. Tenant isolation, ActionCable authentication, CSRF protection, cursor-based pagination, query objects, and concern organization are all implemented well. The review identified **31 actionable findings** including 3 critical issues, all of which have been resolved.

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 3 | All fixed (commit `8431ecb`) |
| High | 11 | Backlog |
| Medium | 17 | Backlog |

---

## Critical — Fixed

### C1. Stored XSS via Custom Styles ~RESOLVED~
**Area:** Security
**File:** `app/helpers/application_helper.rb:29`, `app/controllers/accounts/custom_styles_controller.rb:8`

The `custom_styles` field is rendered with `html_safe` inside a `<style>` tag on every page load for all users:

```ruby
tag.style(custom_styles.to_s.html_safe)
```

An administrator can inject `</style><script>malicious_js</script><style>` to escape the style context and execute arbitrary JavaScript for every user in the workspace. No sanitization is applied.

**Impact:** Full account takeover for every user. An admin could steal session tokens of other admins.

**Recommendation:** Sanitize custom styles before rendering. Strip `</style>` and `<script>` tags, use a CSS-specific sanitizer, or serve custom styles from a separate endpoint with `Content-Type: text/css`.

**Resolution:** Added `gsub(%r{</style}i, "")` to strip style tag breakout sequences before `html_safe` rendering.

---

### C2. SSRF via Bot Webhook URLs ~RESOLVED~
**Area:** Security
**File:** `app/models/webhook.rb:61-76`, `app/controllers/accounts/bots_controller.rb:37`

Bot webhook URLs (`mentions_url`, `everything_url`) have zero validation — no scheme restriction, no private IP checks, no URL format validation. The `Webhook` model has no `validates` statements. Unlike OpenGraph unfurling which uses `RestrictedHTTP::PrivateNetworkGuard`, webhook delivery goes directly to `Net::HTTP`.

An admin can create a bot with `url: "http://169.254.169.254/latest/meta-data/"` to access cloud metadata endpoints, internal services, or localhost.

**Impact:** Access to internal network services, cloud metadata, potential RCE depending on environment.

**Recommendation:** Validate webhook URLs on save — require HTTPS, block private IPs using the existing `PrivateNetworkGuard`. At minimum, validate URL format and scheme.

**Resolution:** Added URL format validation + `PrivateNetworkGuard.resolve` on save. Added runtime SSRF guard with `http.ipaddr` pinning at delivery time to prevent DNS rebinding.

---

### C3. Race Condition in DM Room Creation ~RESOLVED~
**Area:** Data Integrity
**File:** `app/models/rooms/direct.rb:8-11`, `db/schema.rb:218`

`Rooms::Direct.find_or_create_for` does `find_by(members_hash) || create_for(...)` without locking or a uniqueness constraint. The `members_hash` index is **not unique**. Two concurrent requests to create a DM between the same users can both pass the `find_by` check and create duplicate rooms.

**Impact:** Duplicate DM rooms for the same user pair, leading to fragmented conversations.

**Recommendation:** Add a unique index on `members_hash` (filtered to `Rooms::Direct` type) and handle `ActiveRecord::RecordNotUnique` with a retry/find pattern.

**Resolution:** New migration makes `members_hash` index unique. Added `rescue ActiveRecord::RecordNotUnique` with `find_by!` fallback in `find_or_create_for`.

---

## High Severity

### H1. Race Condition in Connection Counter
**Area:** Data Integrity
**File:** `app/models/membership/connectable.rb:26-50`

`present`, `connected`, `disconnected`, `increment_connections`, and `decrement_connections` all perform read-then-write patterns without locking. Multiple concurrent WebSocket connections can cause the `connections` counter to become inconsistent (negative values, lost increments).

**Impact:** Inaccurate connection counts, users showing as offline when connected (or vice versa).

**Recommendation:** Use `with_lock` or atomic SQL: `UPDATE SET connections = connections + 1`.

---

### H2. Missing Foreign Key Constraints
**Area:** Data Integrity
**File:** `db/schema.rb:208, 129, 295-315`

`rooms.creator_id` and `boosts.booster_id` have no foreign key constraints to `users.id`. Every other similar FK relationship has a constraint.

**Impact:** Orphaned records if a user is destroyed.

**Recommendation:** Add `add_foreign_key "rooms", "users", column: "creator_id"` and `add_foreign_key "boosts", "users", column: "booster_id"`.

---

### H3. Missing Uniqueness Constraint on Bookmarks
**Area:** Data Integrity
**File:** `db/schema.rb:123`, `app/models/bookmark.rb`

No `validates_uniqueness_of` and no unique database index on `(user_id, message_id)` for active bookmarks. A user can bookmark the same message multiple times.

**Recommendation:** Add a unique index on `(user_id, message_id)` where `active = true`.

---

### H4. Push Notification N+1 Queries
**Area:** Performance
**File:** `app/models/push/subscription.rb:5`

`Push::Subscription#notification` loads all unread memberships, then calls `has_unread_notifications?` on each — triggering a separate DB query per membership. This fires for **every** push subscription delivery.

**Impact:** Dozens of queries per push notification.

**Recommendation:** Use the existing `with_has_unread_notifications` scope, or compute the badge count once and pass it through the push pipeline.

---

### H5. mark_inbox_as_read Triple Iteration with N+1
**Area:** Performance
**File:** `app/models/user.rb:86-106`

Three separate queries for `memberships.unread`, plus per-membership: `m.room` (no eager load), `m.room.messages.without_user_mentions.between(...)`, and `m.read_until` (which queries again). For a user with 20 unread rooms, this triggers 60+ queries.

**Recommendation:** Consolidate into a single pass, eager-load rooms, and batch the non-mentions check.

---

### H6. Mentionee Sidebar Broadcast Explosion
**Area:** Performance
**File:** `app/models/message/broadcasts.rb:110-121`

`broadcast_mentionee_sidebar_updates` renders the **entire shared rooms list** per mentionee. With `@everyone` in a 100-member room, this could generate 200 partial renders synchronously.

**Recommendation:** Debounce sidebar broadcasts, move to a background job, or use a lighter-weight targeted update.

---

### H7. Disconnected User Broadcast Memory Usage
**Area:** Performance
**File:** `app/models/room.rb:199-212`

`broadcast_unread_to_disconnected_users` loads ALL disconnected visible members into memory via `.map(&:user)`. For large rooms, this means hundreds of User records in memory.

**Recommendation:** Use `find_each` or `pluck(:user_id)` and broadcast by user ID.

---

### H8. Message Creation Callback Chain Latency
**Area:** Performance
**File:** `app/models/message.rb:28-32`

A single message creation triggers 5 `after_create_commit` callbacks plus multiple broadcasts — approximately 10+ DB queries synchronously. The `recalculate_streak!` callback does a complex 4-table join.

**Recommendation:** Move non-critical callbacks (streak calculation, thread updates) to background jobs.

---

### H9. Memory Leak in busy_on_submit_controller
**Area:** Frontend
**File:** `app/javascript/controllers/busy_on_submit_controller.js:21-25`

`.bind(this)` creates a new function reference in `disconnect()`, so `removeEventListener` never matches the original listener added in `connect()`. This leaks an event listener on every connect/disconnect cycle.

**Recommendation:** Store the bound function reference and reuse it, or use the arrow function directly since it already captures `this`.

---

### H10. CSS Selector Injection in filter_controller
**Area:** Frontend
**File:** `app/javascript/controllers/filter_controller.js:42`

User input is interpolated directly into a CSS attribute selector without sanitization:

```javascript
this.listTarget.querySelectorAll(`[data-value*=${value.toLowerCase()}]`)
```

**Recommendation:** Use `CSS.escape()`: `` `[data-value*="${CSS.escape(value.toLowerCase())}"]` ``

---

### H11. Event Listener Leaks in lightbox and PWA Controllers
**Area:** Frontend
**Files:** `app/javascript/controllers/lightbox_controller.js:40-48`, `app/javascript/controllers/pwa_install_controller.js:8-11`

Both controllers add event listeners in `connect()` but have no `disconnect()` method to remove them.

**Recommendation:** Add `disconnect()` methods that remove all listeners added in `connect()`.

---

## Medium Severity

### M1. No Content Security Policy Beyond frame_ancestors
**Area:** Security
**File:** `config/initializers/content_security_policy.rb:27-37`

No `script-src`, `style-src`, `default-src`, or `connect-src` directives. This removes a key defense-in-depth layer against XSS (compounding C1).

**Recommendation:** Add comprehensive CSP with `default-src 'self'`, `script-src`, `style-src` directives.

---

### M2. Bot Error Handler Exposes Exception Details
**Area:** Security
**File:** `app/controllers/rooms/directs/by_bots_controller.rb:11-13`

`rescue_from Exception` returns `error.message` in JSON, potentially leaking internal paths, DB errors, and configuration.

**Recommendation:** Return generic error messages. Log the full exception server-side.

---

### M3. Mass Assignment on Account Settings
**Area:** Security
**File:** `app/controllers/accounts_controller.rb:21`

`settings: {}` permits any key in the settings hash. An admin could inject arbitrary keys that future code might read.

**Recommendation:** Restrict to known keys: `settings: [:restrict_room_creation_to_administrators, :restrict_direct_messages_to_administrators, :allow_users_to_create_invite_links]`.

---

### M4. Session Transfer Endpoint — No Rate Limiting
**Area:** Security
**File:** `app/controllers/sessions/transfers_controller.rb:1-15`

The unauthenticated `update` action accepts signed transfer IDs with a 4-hour expiry window but has no rate limiting.

**Recommendation:** Add rate limiting (e.g., 5 attempts per IP per minute).

---

### M5. InboxesController Has 6 Non-RESTful Actions
**Area:** Architecture
**File:** `app/controllers/inboxes_controller.rb:13-58`

Actions `activity`, `direct_messages`, `threads`, `notifications`, `messages`, `bookmarks`, `clear` violate the project's own CLAUDE.md convention against custom controller actions. The paged sub-controllers already exist.

**Recommendation:** Use the existing sub-controllers (`Inboxes::ActivityController`, etc.) and extract `clear` to `Inbox::ReadsController#destroy`.

---

### M6. UsersController#create Contains ~100 Lines of Business Logic
**Area:** Architecture
**File:** `app/controllers/users_controller.rb:25-128`

Branching for SaaS/self-hosted, join code redemption, cleanup, OTP flow — all in the controller.

**Recommendation:** Extract to a model or service object (e.g., `User::Registration`).

---

### M7. Side-Effecting GET in ThreadsController#new
**Area:** Architecture
**File:** `app/controllers/rooms/threads_controller.rb:6-16`

The `new` action creates a thread room and redirects. GET requests should not have side effects.

**Recommendation:** Move creation logic to a `create` action triggered by POST.

---

### M8. ~12 Non-RESTful Actions Across Controllers
**Area:** Architecture
**Files:** Multiple controllers

| Controller | Action | Should Be |
|-----------|--------|-----------|
| `Accounts::UsersController` | `reactivate` | `Accounts::Users::ReactivationsController#create` |
| `Users::ProfilesController` | `cancel_email_change` | `Users::EmailChangesController#destroy` |
| `Users::ProfilesController` | `shuffle_avatar` | `Users::AvatarShufflesController#create` |
| `Users::SidebarsController` | `hidden_rooms` | `Users::HiddenRoomsController#index` |
| `Rooms::InvolvementsController` | `notifications_ready` | `Rooms::NotificationsReadyController#show` |
| `Rooms::ClosedsController` | `users` | `Rooms::Closeds::UsersController#index` |
| `SearchesController` | `page`, `clear` | Standard pagination / `#destroy` |

---

### M9. Missing Index on rooms(type, active)
**Area:** Performance
**File:** `db/schema.rb:205-221`

No index on `rooms.type` at all. Every membership scope that joins rooms and filters by type does a sequential scan.

**Recommendation:** Add `index :rooms, [:type, :active]` and `index :rooms, [:active, :last_active_at]`.

---

### M10. UnfurlLinksController Blocks Puma Thread
**Area:** Performance
**File:** `app/controllers/unfurl_links_controller.rb:3`

Synchronous HTTP fetching (DNS + fetch + up to 10 redirects) blocks a Puma thread. A slow target URL can block for 30+ seconds.

**Recommendation:** Move to a background job or add explicit timeouts (5s open, 5s read).

---

### M11. posted_on? DATE() Prevents Index Usage
**Area:** Performance
**File:** `app/models/user.rb:250-258`

`DATE(messages.created_at)` wrapping prevents SQLite from using the index. Called on every non-DM message create via `recalculate_streak!`.

**Recommendation:** Use range query: `where(created_at: date.beginning_of_day...date.tomorrow.beginning_of_day)`.

---

### M12. DB/Model Validation Mismatches
**Area:** Data Integrity
**Files:** `db/schema.rb:78-82`, `app/models/user.rb:125-128`

- `auth_tokens` columns allow NULL at DB level despite model validations requiring presence
- `User.email_address` uniqueness is only enforced at DB level — violations raise `RecordNotUnique` instead of user-friendly errors

**Recommendation:** Add NOT NULL constraints to match model validations. Add `validates :email_address, uniqueness: true` to User.

---

### M13. Mentions Table Has No Uniqueness Constraint
**Area:** Data Integrity
**File:** `db/schema.rb:168`

The `mentions` table (`id: false`) has no unique index on `(message_id, user_id)`. `Mention.insert_all` in `Message::Mentionee` does not prevent duplicates at the DB level.

**Recommendation:** Add a unique index on `(message_id, user_id)`.

---

### M14. Boost Uniqueness Validation Without DB Constraint
**Area:** Data Integrity
**File:** `app/models/boost.rb:7`

Model validates uniqueness scoped to active boosts, but there's no corresponding DB unique index. TOCTOU-vulnerable under concurrency.

**Recommendation:** Add a partial unique index on `(content, message_id, booster_id)` where `active = true`.

---

### M15. ~REMOVED~ Room Merge Feature Removed
**Area:** Data Integrity

The room merge feature was removed entirely due to multiple integrity concerns (thread orphaning, counter cache outside transaction, no test coverage for associated data).

---

### M16. Stale Async Callbacks in presence_controller
**Area:** Frontend
**File:** `app/javascript/controllers/presence_controller.js:47-65`

`await delay(5000)` in `#visible` and `#hidden` has no cancellation. If the controller disconnects during the delay, the callback executes on a disconnected controller.

**Recommendation:** Use an `AbortController` or flag to skip execution after disconnect.

---

### M17. Missing disconnect() in inbox_controller
**Area:** Frontend
**File:** `app/javascript/controllers/inbox_controller.js:23-31`

Creates a `MessagePaginator` with `monitor()` in `connect()` but has no `disconnect()`. The paginator's internal `ScrollTracker` (MutationObserver + IntersectionObserver) is never cleaned up.

**Recommendation:** Add `disconnect()` that calls `this.paginator.disconnect()`.

---

## Positive Findings

The review identified many well-implemented patterns:

**Security:**
- Session fixation prevention (session reset before new session)
- CSRF protection enabled globally (except bot API key auth)
- ActionCable connection auth validates sessions, rejects banned/deactivated users
- FTS5 search uses parameterized queries (no SQL injection)
- OpenGraph SSRF protection via `PrivateNetworkGuard` is thorough
- SaaS tenant isolation is architecturally sound (database-per-tenant)

**Architecture:**
- Clean model concern organization with single-responsibility concerns
- Well-designed STI Room hierarchy with proper overrides
- Excellent query object pattern (`Inbox::*Query`, `SidebarMemberships`)
- Dual-mode (self-hosted/SaaS) architecture is impressively clean
- Most controllers are thin and focused (5-10 lines per action)

**Performance:**
- Counter caches on `rooms.messages_count`
- Cursor-based pagination (not offset) — excellent for SQLite
- Batch operations via `upsert_all` and `insert_all`
- Redis cache for active_member_count with TTL
- WebPush::Pool with thread pool + persistent HTTP connections
- Throttled room broadcasts via Redis locking

**Frontend:**
- Turbo preview handling (`pageIsTurboPreview()` checks)
- Brief disconnect handling prevents premature channel teardown
- Debounced/throttled network calls in search and typing
- HTML escaping for filenames in composer
- Accessibility: skip-nav links, ARIA labels, flash live regions, focus trap

**Data Integrity:**
- Soft deletion thoroughly implemented with proper `unscoped` cleanup
- Comprehensive foreign key coverage (with noted exceptions)
- Transaction boundaries generally correct
- Type-safe `has_json` settings pattern

---

## Recommended Remediation Priority

| Priority | Item | Effort | Status |
|----------|------|--------|--------|
| ~~1~~ | ~~Sanitize `custom_styles` (C1)~~ | ~~Small~~ | Done |
| ~~2~~ | ~~Add SSRF protection to webhooks (C2)~~ | ~~Small~~ | Done |
| ~~3~~ | ~~Unique constraint on `members_hash` (C3)~~ | ~~Small~~ | Done |
| 4 | Atomic connection counter updates (H1) | Small |
| 5 | Add comprehensive CSP headers (M1) | Medium |
| 6 | Add missing FK constraints (H2) | Small |
| 7 | Fix JS memory leaks — bind, lightbox, PWA, inbox (H9-H11, M17) | Small |
| 8 | Fix N+1 in push notifications (H4) | Medium |
| 9 | Fix N+1 in mark_inbox_as_read (H5) | Medium |
| 10 | Add `rooms(type, active)` index (M9) | Small |
| 11 | Move unfurl to background job (M10) | Medium |
| 12 | Refactor InboxesController (M5) | Medium |
| 13 | Extract UsersController#create logic (M6) | Medium |
| 14 | Add missing uniqueness constraints — bookmarks, mentions, boosts (H3, M13, M14) | Small |
| 15 | Fix posted_on? date query (M11) | Small |

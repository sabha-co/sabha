# Soft Deletion and User States

This document explains the soft deletion patterns and user state management in Sabha.

## Table of Contents

1. [Overview](#overview)
2. [Room Deactivation](#room-deactivation)
3. [User States](#user-states)
4. [Message Deletion](#message-deletion)
5. [Other Soft-Deleted Models](#other-soft-deleted-models)

---

## Overview

Sabha uses soft deletion for most content. Records are marked `active: false` rather than destroyed, preserving data for potential recovery and maintaining referential integrity.

### Deactivatable Concern

**File:** `app/models/concerns/deactivatable.rb`

Provides:
- `scope :active` - `where(active: true)`
- `scope :inactive` - `where(active: false)`
- `deactivate!` / `activate!` - Toggle the boolean
- `deactivated?` - Returns `!active?`

`Deactivatable` does **not** install a `default_scope`. Soft-deleted records remain visible to plain `Model.find` and to `Model.where(...)` queries; only association-level `-> { active }` scopes hide them. Code never needs `unscoped` to reach inactive rows.

### Models Using Soft Deletion

| Model | Has Custom Logic? | Reactivation? |
|-------|-------------------|---------------|
| Room | Yes | Console only |
| User | Yes (status enum) | Admin UI or console |
| Message | Yes | Console only |
| Membership | No | Via Room/User reactivation |
| Bookmark | No (hard-deleted) | No (user creates new) |
| Boost | No (hard-deleted) | No (user creates new) |

---

## Room Deactivation

Rooms use the `active` boolean via `Deactivatable`. Each room type behaves slightly differently.

### Rooms::Open and Rooms::Closed

**Triggered by:** Admin deletes room from UI

**File:** `app/models/room.rb`

```ruby
def deactivate
  raise CannotDeleteOriginalError if original?

  transaction do
    deactivate_threads
    memberships.update_all(active: false)
    Message.where(room_id: id).update_all(active: false)
    destroy_notifications_for_messages
    deactivate!
  end
end
```

| Action | Effect |
|--------|--------|
| Threads | All threads from this room deactivated |
| Memberships | All marked `active: false` |
| Messages | All marked `active: false` |
| Room | Marked `active: false` |

**Result:** Room disappears from sidebar for all users.

### Rooms::Direct

Direct messages are not exposed to deletion in UI. When a user is deactivated, their DM memberships are intentionally preserved so other participants can still see conversation history.

### Rooms::Thread

**Triggered by:**
1. Admin deletes thread directly from UI
2. Parent room is deactivated (cascades)

**File:** `app/models/rooms/thread.rb`

```ruby
def deactivate
  transaction do
    Membership.where(room_id: id).update_all(active: false)
    Message.where(room_id: id).update_all(active: false)
    deactivate!
  end
end
```

**Note:** Deleting the parent *message* does NOT deactivate the thread. The thread remains accessible with a "deleted message" indicator.

### Room Reactivation

**Triggered by:** Console only (no UI)

```ruby
def reactivate
  transaction do
    reactivate_threads
    memberships.rewhere(active: false).update_all(active: true)
    Message.where(room_id: id, active: false).update_all(active: true)
    activate!
  end
end
```

Restores all related records including threads. `Room::Restorable#broadcast_reactivation_if_restored` (fired by `activate!`'s commit) broadcasts the room's reappearance to the sidebar.

## User States

Users have a `status` enum instead of a simple boolean.

**File:** `app/models/user.rb`

```ruby
enum :status, %i[active deactivated banned], default: :active
```

### State Comparison

| State | Can Login | Messages | Session IPs banned |
|-------|-----------|----------|--------------------|
| `active` | Yes | Visible | No |
| `deactivated` | No | Visible | No |
| `banned` | No | Soft-deleted | Yes |

**Key distinction:**
- **Deactivate** = account closure (preserves contributions)
- **Ban** = punitive action (removes content + blocks the IPs the user was last seen on)
- **Block** = peer-to-peer DM/mention suppression between two users, unrelated to account status (`User::Blockable`; see [PERMISSIONS.md](PERMISSIONS.md#blocks-vs-bans))

### Shared Access Revocation

Both deactivation and banning share a common `revoke_access` method:

**File:** `app/models/user.rb`

```ruby
def revoke_access
  close_remote_connections
  memberships.without_direct_rooms.update!(active: false)
  push_subscriptions.delete_all
  sessions.delete_all
  auth_tokens.delete_all
end
```

This method:
- Disconnects WebSocket connections
- Deactivates non-DM memberships
- Deletes push subscriptions
- Deletes sessions (logs out everywhere)
- Deletes auth tokens (invalidates magic links)

**Note:** `revoke_access` itself excludes DMs (`without_direct_rooms`). User-level deactivation then calls `deactivate_direct_rooms` separately, which **does** flip those DM rooms inactive. The exclusion in `revoke_access` exists for paths that share the helper but don't want to nuke DMs (e.g. session/auth token revocation alone).

### User Deactivation

**Triggered by:** Admin deactivates user from UI

```ruby
def deactivate
  transaction do
    revoke_access
    deactivate_direct_rooms
    searches.delete_all
    update! status: :deactivated
  end
end
```

| Action | Effect |
|--------|--------|
| Access | Revoked (see above) |
| Direct rooms | Each DM room is deactivated via `User#deactivate_direct_rooms`, which cascades through `Room#deactivate` — so the other participant's membership in that DM is also flipped to `active: false`. Open/Closed memberships were already deactivated by `revoke_access`; this step covers the DM rooms `revoke_access` skipped. |
| Searches | Deleted |
| Messages | Unchanged (remain visible in still-active rooms; hidden in DMs that just deactivated) |
| Status | Set to `deactivated` |

### User Reactivation

**Triggered by:** Admin reactivates user from UI (only for deactivated users, not banned)

**File:** `app/controllers/accounts/users_controller.rb`

```ruby
def reactivate
  @user.reactivate if @user.deactivated?
  redirect_to account_users_url
end
```

**File:** `app/models/user.rb`

```ruby
def reactivate
  transaction do
    # rewhere(active: false) replaces the default `active` scope to find inactive memberships
    memberships.rewhere(active: false).without_direct_rooms.update!(active: true)
    reactivate_direct_rooms
    update! status: :active
    reset_remote_connections
  end
end
```

Restores memberships and direct rooms, sets status back to active. User must request new password/magic link.

**Note:** Banned users cannot be reactivated via this action - they must be unbanned first.

### User Ban

**Triggered by:** Admin bans user from UI

**File:** `app/models/user/bannable.rb`

```ruby
def ban
  transaction do
    create_bans_from_sessions
    apply_ban
    banned!
  end
end

private

def apply_ban
  revoke_access  # calls User#revoke_access (shared with deactivate)
  remove_banned_content_later
end
```

| Action | Effect |
|--------|--------|
| IP addresses | All session IPs added to `bans` table |
| Access | Revoked via `revoke_access` (see above) |
| Messages | Deactivated via `RemoveBannedContentJob` |
| Status | Set to `banned` |

**IP Blocking:** `BlockBannedRequests` concern returns `429 Too Many Requests` for **all** requests (every verb) from banned IPs.

**Authentication:** Both banned and deactivated users are blocked in `authenticated_as` (`app/controllers/concerns/authentication.rb`). In SaaS mode, an inactive workspace user is additionally redirected to `/settings?denied=workspace` via `deny_inactive_workspace_user`.

### User Unban

```ruby
def unban
  transaction do
    bans.delete_all
    active!
  end
end
```

Removes IP bans and restores status. Messages remain deactivated (manual recovery required).

---

## Message Deletion

**Triggered by:** User deletes their own message from UI

**File:** `app/models/message.rb`

Messages use `Deactivatable` with additional logic:

1. **Unread timestamp cleanup:** When deleted, finds memberships where `unread_at` pointed to this message and updates to next unread.
2. **Thread broadcast:** If the message has threads, broadcasts an update to show the "deleted message" indicator.
3. **Restoration broadcast:** If a previously deactivated message is restored, re-broadcasts it into the room.

```ruby
# app/models/message.rb
after_update_commit :clear_unread_timestamps_if_deactivated  # in Message::Unreadable
after_update_commit :broadcast_parent_message_to_threads     # in Message::Threadable
after_update_commit :broadcast_reactivation_if_restored
```

**Note:** Deleting a message does NOT delete its thread. The thread remains accessible.

---

## Other Soft-Deleted Models

### Membership

Never deactivated as a standalone user action. Flipped to `active: false` only as part of:
- Room deactivation
- User deactivation / banning (via `revoke_access`)
- `Membership#revoke_from` when an admin removes a user from a room

**User-initiated "leave room" is different.** `Membership#leave!` keeps `active: true` and sets `involvement: :invisible` — the row persists so historical messages still resolve, and the user can be re-added later without losing audit trail. The last visible member of a Closed room cannot leave (`Membership::LastVisibleMemberError`); the room must be deleted instead. DMs cannot be "left" at all — the API rejects the call.

### Bookmark

Hard-deleted when user removes a bookmark. User creates a new bookmark to re-add.

### Boost

Hard-deleted when user removes a reaction. Has `broadcast_removal` callback to update the UI in real-time.

---

## Hard Deletion

A handful of paths bypass soft deletion entirely — primarily when a record is being purged for compliance or when a parent is being destroyed. Each model that participates in hard deletion overrides `destroy_all_associated_records` to control cascade order, because some associations use `-> { active }` scopes and would silently leave inactive rows behind under default `dependent: :destroy`.

> **Adding a new `has_many` to User, Room, or Message? Update `destroy_all_associated_records`.** The active-scope gotcha applies to every model that uses `Deactivatable`.

### `User#destroy_all_associated_records`

Order matters because of foreign-key fan-out and SaaS untenanted models:

1. `Notification.delete_all_and_broadcast` for any notifications addressed to the user
2. Soft-deleted messages still owned by the user (hard-deleted now)
3. Memberships (including inactive ones, which the default association scope skips)
4. `WorkspaceMembership.user_id` nulled out in the untenanted DB so the global identity doesn't dangling-reference a deleted tenant user
5. Bundle items, push subscriptions, sessions, auth tokens — anything not covered by `dependent:` on the association

### `Room#destroy_all_associated_records`

Threads first (because they hold messages), then messages, then memberships. Storage blobs from message attachments are intentionally *not* purged here — Active Storage's own purge job handles them.

### `Message#destroy_all_associated_records`

`Notification.delete_all_and_broadcast`, `rebalance_unread_counters` on affected memberships, then Boost / Bookmark / BundleItem cleanup. Storage blobs are preserved (same reason as Room).

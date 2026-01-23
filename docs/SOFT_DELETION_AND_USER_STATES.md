# Soft Deletion and User States

This document explains the soft deletion patterns and user state management in Campfire.

## Table of Contents

1. [Overview](#overview)
2. [Room Deactivation](#room-deactivation)
3. [User States](#user-states)
4. [Message Deletion](#message-deletion)
5. [Other Soft-Deleted Models](#other-soft-deleted-models)

---

## Overview

Campfire uses soft deletion for most content. Records are marked `active: false` rather than destroyed, preserving data for potential recovery and maintaining referential integrity.

### Deactivatable Concern

**File:** `app/models/concerns/deactivatable.rb`

Provides:
- `scope :active` - `where(active: true)`
- `scope :inactive` - `where(active: false)`
- `deactivate!` / `activate!` - Toggle the boolean
- `deactivated?` - Returns `!active?`

### Models Using Soft Deletion

| Model | Has Custom Logic? | Reactivation? |
|-------|-------------------|---------------|
| Room | Yes | Console only |
| User | Yes (status enum) | Admin UI or console |
| Message | Yes | Console only |
| Membership | No | Via Room/User reactivation |
| Bookmark | No | No (user creates new) |
| Boost | No | Console only |

---

## Room Deactivation

Rooms use the `active` boolean via `Deactivatable`. Each room type behaves slightly differently.

### Rooms::Open and Rooms::Closed

**Triggered by:** Admin deletes room from UI

**File:** `app/models/room.rb`

```ruby
def deactivate
  transaction do
    deactivate_threads
    memberships.update_all(active: false)
    Message.unscoped.where(room_id: id).update_all(active: false)
    update!(slug: nil) if slug.present?
    deactivate!
  end
end
```

| Action | Effect |
|--------|--------|
| Threads | All threads from this room deactivated |
| Memberships | All marked `active: false` |
| Messages | All marked `active: false` |
| Slug | Cleared (freed for reuse) |
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
    Message.unscoped.where(room_id: id).update_all(active: false)
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
    Message.unscoped.where(room_id: id, active: false).update_all(active: true)
    activate!
  end
end
```

Restores all related records including threads. Broadcasts room reappearance to sidebar.

### Room Merge

Merges one room into another, moving all messages (including inactive ones).

```ruby
def merge_into!(target_room)
  transaction do
    memberships.update(active: false)
    Message.unscoped.where(room_id: id).update_all(room_id: target_room.id)
    Message::RichTextUpdater.update_room_links_in_quoted_messages(from: id, to: target_room.id)
    update!(slug: nil) if slug.present?
    deactivate!
  end

  Room.reset_counters(id, :messages)
  Room.reset_counters(target_room.id, :messages)
end
```

---

## User States

Users have a `status` enum instead of a simple boolean.

**File:** `app/models/user.rb`

```ruby
enum :status, %i[active deactivated banned], default: :active
```

### State Comparison

| State | Can Login | Messages | IP Blocked |
|-------|-----------|----------|------------|
| `active` | Yes | Visible | No |
| `deactivated` | No | Visible | No |
| `banned` | No | Soft-deleted | Yes |

**Key distinction:**
- **Deactivate** = account closure (preserves contributions)
- **Ban** = punitive action (removes content)

### Shared Access Revocation

Both deactivation and banning share a common `revoke_access` method:

**File:** `app/models/user.rb`

```ruby
def revoke_access
  close_remote_connections
  memberships.without_direct_rooms.update!(active: false)
  push_subscriptions.delete_all
  searches.delete_all
  sessions.delete_all
  auth_tokens.delete_all
end
```

This method:
- Disconnects WebSocket connections
- Deactivates non-DM memberships
- Deletes push subscriptions
- Deletes searches
- Deletes sessions (logs out everywhere)
- Deletes auth tokens (invalidates magic links)

**Note:** DM memberships preserved so other participants can still see conversation history.

### User Deactivation

**Triggered by:** Admin deactivates user from UI

```ruby
def deactivate
  transaction do
    revoke_access
    deactivated!
  end
end
```

| Action | Effect |
|--------|--------|
| Access | Revoked (see above) |
| Messages | Unchanged (remain visible) |
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
    active!
    reset_remote_connections
  end
end
```

Restores memberships and sets status back to active. User must request new password/magic link.

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

**IP Blocking:** `BlockBannedRequests` concern blocks all non-GET/HEAD requests from banned IPs (returns 429).

**Authentication:** Both banned and deactivated users are blocked in `authenticated_as`.

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

1. **Unread timestamp cleanup:** When deleted, finds memberships where `unread_at` pointed to this message and updates to next unread
2. **Thread broadcast:** If message has threads, broadcasts update to show "deleted message" indicator

```ruby
after_update_commit :clear_unread_timestamps_if_deactivated
after_update_commit :broadcast_parent_message_to_threads
```

**Note:** Deleting a message does NOT delete its thread. The thread remains accessible.

---

## Other Soft-Deleted Models

### Membership

Never deactivated directly. Deactivated as part of:
- Room deactivation
- User deactivation
- `revoke_from` when user is removed from room

### Bookmark

Deactivated when user removes a bookmark. No custom logic - just toggles `active` boolean. User creates a new bookmark to re-add.

### Boost

Deactivated when user removes a reaction. Has `broadcast_reactivation` callback but no custom deactivation logic.

---

## Test Coverage

Tests verify:

**Room:**
- Room deactivation sets room/memberships/messages to inactive
- Room deactivation cascades to thread rooms
- Room reactivation restores room/memberships/messages/threads
- Room merge moves all messages (including inactive)

**User Deactivation:**
- User deactivation deletes sessions, auth_tokens, push subscriptions
- User deactivation deactivates non-DM memberships
- User reactivation restores memberships
- Deactivated users cannot authenticate

**User Ban:**
- Ban creates ban records from sessions
- Ban destroys sessions
- Ban enqueues content removal job
- Ban deactivates non-DM memberships
- Ban deletes auth tokens
- Ban deletes push subscriptions
- Ban soft-deletes messages
- Non-admins cannot ban/unban
- IP blocking for banned users

**Admin UI:**
- Admin can deactivate user
- Admin can reactivate deactivated user
- Non-admins cannot reactivate
- Reactivate does not work on banned users (must unban first)
- Reactivate does not work on active users
- Deactivated users filter in admin panel

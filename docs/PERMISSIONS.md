# Permissions

This document outlines the permission system for rooms and actions in Sabha.

## Room Types

| Type | Description |
|------|-------------|
| **Open** | Public rooms accessible to all members |
| **Closed** | Private invite-only rooms |
| **Direct** | 1-on-1 or group direct messages |
| **Thread** | Discussion threads tied to a parent message |

## Permission Matrix

| Room Type | Create | Read | Update | Delete |
|-----------|--------|------|--------|--------|
| **Direct** | Any user* | Members | N/A | Any member |
| **Open** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Closed** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Thread** | Any user | Members | Members | Admin/Creator |

*Can be restricted to admins via Account Settings

## Permission Logic

### `can_administer?(record)`

Located in `app/models/user/role.rb`. Returns `true` if:

1. User is an **administrator**, OR
2. User is the **creator** of the record, OR
3. Record is new (unsaved)

```ruby
def can_administer?(record = nil)
  administrator? || self == record&.creator || record&.new_record?
end
```

### Direct Messages (DMs)

DMs have relaxed permissions - any member can delete the conversation. This is handled by skipping the `ensure_can_administer` callback in `Rooms::DirectsController`.

## Account Settings

Administrators can restrict creation permissions via Account Settings (`/account/edit`):

| Setting | Effect |
|---------|--------|
| `restrict_room_creation_to_administrators?` | Only admins can create Open/Closed rooms |
| `restrict_direct_messages_to_administrators?` | Only admins can initiate DMs |

These settings are stored in `accounts.settings` JSON column.

## Controller Callbacks

### RoomsController (Base)

```ruby
before_action :set_room, only: %i[ show destroy ]
before_action :ensure_can_administer, only: %i[ destroy ]
```

### Rooms::DirectsController

```ruby
skip_before_action :set_room, only: %i[ edit destroy ]
skip_before_action :ensure_can_administer, only: %i[ destroy ]
before_action :set_direct_room, only: %i[ edit destroy ]
```

### Rooms::OpensController / Rooms::ClosedsController

```ruby
before_action :set_room, only: %i[ show edit update destroy ]
before_action :ensure_can_administer, only: %i[ update destroy ]
before_action :ensure_permission_to_create_rooms, only: %i[ new create ]
```

### Rooms::ThreadsController

```ruby
before_action :set_room, only: %i[ edit update destroy ]
```

## Membership Involvement Levels

Users can set their involvement level for each room:

| Level | Description | Available For |
|-------|-------------|---------------|
| `everything` | All notifications, appears in "My Rooms" | All room types |
| `mentions` | Only @mention notifications, appears in "All Rooms" | Open, Closed |
| `nothing` | No notifications | Direct only |
| `invisible` | Hidden from sidebar entirely | Open, Closed |

Note: DMs only cycle between `everything` and `nothing` in the UI.

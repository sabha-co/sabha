# Permissions

## Roles

Sabha has four user roles defined in `app/models/user/role.rb`:

| Role | Description |
|------|-------------|
| **Member** | Regular user, default role |
| **Moderator** | Staff role — can moderate messages and view banned/deactivated users |
| **Administrator** | Full control over account, users, rooms, and settings |
| **Bot** | Automated user for integrations |

Key predicates:

- `staff?` — true for moderator or administrator
- `can_moderate?` — alias for `staff?`
- `can_administer?(record)` — true if administrator, record creator, or new record
- `person?` — true if not a bot

## Room Types

| Type | Description |
|------|-------------|
| **Open** | Public rooms accessible to all members |
| **Closed** | Private invite-only rooms |
| **Direct** | 1-on-1 or group direct messages |
| **Thread** | Discussion threads tied to a parent message |

## Room Permission Matrix

| Room Type | Create | Read | Update | Delete |
|-----------|--------|------|--------|--------|
| **Direct** | Any user* | Members | N/A | Any member |
| **Open** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Closed** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Thread** | Any user | Members | Admin/Creator | Admin/Creator |

*Can be restricted to admins via Account Settings

## Message Permission Matrix

| Action | Who Can Perform |
|--------|----------------|
| Create | Any active member in the room |
| Edit own | Author |
| Delete own | Author |
| Edit others' | Moderator, Administrator |
| Delete others' | Moderator, Administrator |

Checked via `can_edit_message?(message)` and `can_delete_message?(message)` — both return true for `can_moderate? || message.creator == self`.

## User Management Permissions

All user management actions require administrator role:

| Action | Required Role | Method |
|--------|--------------|--------|
| Change user role | Administrator | `manageable_by?(admin)` |
| Deactivate user | Administrator | `removable_by?(admin)` |
| Ban user | Administrator | `removable_by?(admin)` |
| Unban user | Administrator | `unbannable_by?(admin)` |
| Reactivate user | Administrator | `reactivatable_by?(admin)` |

Moderators can view banned and deactivated user lists but cannot take action on them.

## Notes

**Direct Messages** have relaxed permissions — any member can delete the conversation (skips `ensure_can_administer`).

## Account Settings

Administrators can restrict permissions via Account Settings (`/account/edit`):

| Setting | Effect |
|---------|--------|
| `restrict_room_creation_to_administrators?` | Only admins can create Open/Closed rooms |
| `restrict_direct_messages_to_administrators?` | Only admins can initiate DMs |
| `allow_users_to_create_invite_links?` | When false, only admins can create invite links (default: true) |

These settings are stored in `accounts.settings` JSON column.

## Membership Involvement Levels

Users can set their involvement level for each room:

| Level | Description | Available For |
|-------|-------------|---------------|
| `everything` | All notifications, appears in "My Rooms" | All room types |
| `mentions` | Only @mention notifications, appears in "All Rooms" | Open, Closed |
| `nothing` | No notifications | Direct only |
| `invisible` | User has left the room — membership persists for history but is hidden from sidebar and room lists | Open, Closed |

Note: DMs only cycle between `everything` and `nothing` in the UI.

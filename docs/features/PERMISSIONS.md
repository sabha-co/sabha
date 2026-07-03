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
| **Forum** | Gallery of titled posts; each post is a `Rooms::Thread` (see `FORUMS.md`) |
| **Thread** | Discussion threads tied to a parent message |

## Room Permission Matrix

| Room Type | Create | Read | Update | Delete |
|-----------|--------|------|--------|--------|
| **Direct** | Any user* | Members | N/A | Any member of the DM |
| **Open** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Closed** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Forum** | Any user* | Members | Admin/Creator | Admin/Creator |
| **Thread** | Any member of the parent room† | Members | Admin/Creator | Admin/Creator |

\* Can be restricted to admins via Account Settings (see below).
† Parent must be a message in an Open or Closed room; threads cannot be created on Direct or Thread messages.

Forum **posts** are `Rooms::Thread`s: any forum member can create one, but editing a post's title or toggling its solved state is limited to an administrator or the post's creator. "Copy link" (the canonical `/f/:slug` URL) is available to every viewer.

Open rooms with `auto_join: true` grant membership to all existing users and to every new signup (`Rooms::Open#auto_join`). The original "All Talk" room cannot be deleted (`Room::CannotDeleteOriginalError`).

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

**Direct Messages** have relaxed permissions — any member of the DM can delete the conversation (skips `ensure_can_administer` but is still scoped to `Current.user.rooms`).

**Leaving a room** uses `Membership#leave!`, which sets `involvement: :invisible` and keeps `active: true` — the membership row persists so historical messages still resolve. The last visible member of a Closed room cannot leave (`Membership::LastVisibleMemberError`); the room must be deleted instead.

## Blocks vs bans

Two distinct mechanisms suppress unwanted contact:

- **Blocks** (`User::Blockable`) — peer-to-peer, DM-scoped. Either party blocking the other prevents new DMs and `@`-mentions between them (`can_ping?` / `can_direct_message?`). No admin involvement; reversible from the user's settings.
- **Bans** (`User::Bannable`) — admin action, account-wide. Collects IPs from the user's sessions, terminates them, soft-deletes their messages via `RemoveBannedContentJob`, and rejects future requests from those IPs with `429 Too Many Requests` (`BlockBannedRequests`). Sends `UserMailer.banned` / `unbanned`.

## Account Settings

Administrators can restrict permissions via Account Settings (`/account/edit`):

| Setting | Effect | Enforced by |
|---------|--------|-------------|
| `restrict_room_creation_to_administrators?` | Only admins can create Open/Closed rooms | `RoomsController#ensure_permission_to_create_rooms` |
| `restrict_direct_messages_to_administrators?` | Only admins can initiate DMs | `User#can_create_direct_messages?` (used in `Rooms::DirectsController`) |
| `allow_users_to_create_invite_links?` | When false, only admins can create invite links (default: true). Flipping false invalidates personal codes. | `Users::InviteLinksController#ensure_can_create_invite_links` |

These settings are stored in the `accounts.settings` JSON column.

**Bots** have their own admin-only surface: per-room involvement (`Accounts::Bots::RoomPermissionsController`) and invite codes (`Accounts::BotInviteCodesController`). The bot role itself cannot be granted through the user-role UI (`AccountsController` strips any `role` value outside `member|moderator|administrator`).

## Membership Involvement Levels

Each membership stores an involvement (`app/models/membership/involvable.rb`). The stored value is one of:

| Level | Behavior |
|-------|----------|
| `everything` | All notifications |
| `mentions` | Only `@`-mention notifications |
| `nothing` | No notifications |
| `invisible` | User has left the room — membership persists for history but is hidden from sidebar and room lists |

The effective involvement is the per-room value layered over the user's global notification mode: a user whose global mode is `nothing` has `effective_involvement == :nothing` for every room regardless of the per-room value. The room-settings UI exposes a subset per room type (DMs cycle `everything`/`nothing`; bot per-room permissions surface `mentions` and `nothing` as "Muted"), but the full enum is accepted on any room type via API or console.

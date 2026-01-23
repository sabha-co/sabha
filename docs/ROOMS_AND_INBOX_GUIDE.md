# Campfire Rooms & Inbox Guide

This guide explains how rooms, notifications, and inbox features work in Campfire.

---

## Part 1: Room Types

Campfire has four types of rooms, each designed for different communication needs.

### Open Rooms

**What they are:** Public rooms accessible to everyone in your workspace.

**Key characteristics:**
- All active users (including bots) automatically join when the room is created
- Anyone can post messages
- Appear in the "All Rooms" section of the sidebar
- Great for company-wide announcements, general discussions, or topic-based channels

**Who can create them:** Administrators, or all members if allowed in settings.

**Examples:** #general, #announcements, #random, #help

---

### Closed Rooms

**What they are:** Private, invite-only rooms for specific groups.

**Key characteristics:**
- Only invited members can see and access the room
- Room creator or admin manages membership
- Appear in sidebar only for members
- Ideal for teams, projects, or sensitive discussions

**Who can create them:** Administrators, or all members if allowed in settings.

**Examples:** #engineering-team, #q4-planning, #hr-confidential

---

### Direct Messages (Pings)

**What they are:** Private conversations between specific people.

**Key characteristics:**
- Can be 1-on-1 or group conversations (3+ people)
- Appear in the horizontal scrolling area at the top of the sidebar
- All participants receive notifications for every message by default
- Creating a DM with the same people always returns the same room (no duplicates)

**Sidebar visibility:** DMs only appear in the sidebar if they are:
- Unread (have new messages), OR
- Recently active (updated within the last 7 days)

Older DMs without activity are hidden from the sidebar but can be found via search or the All Messages inbox.

**Special cases:**
- **Note to self:** Create a DM with just yourself for personal notes
- **Group DMs:** Add multiple people for small group discussions without creating a formal room

**Who can create them:** All members, or administrators only if restricted in settings.

---

### Threads

**What they are:** Focused side conversations attached to a specific message.

**Key characteristics:**
- Created by clicking "Reply in thread" on any message
- Keep detailed discussions from cluttering the main room
- All parent room members automatically get thread membership (with `invisible` involvement by default)
- Threads appear in the Threads inbox, not the sidebar

**Who sees threads:**
- The thread creator (gets `everything` involvement)
- The original message author (gets `everything` involvement)
- Anyone who replies in the thread
- Anyone with "My Rooms" involvement in the parent room

---

## Part 2: Room Involvement (Notification Settings)

Each room has an involvement level that controls notifications and where it appears in your sidebar.

### Involvement Levels

| Level | Sidebar Location | Notifications | Use Case |
|-------|------------------|---------------|----------|
| **My Rooms** | "My Rooms" section | All messages | Rooms you actively follow |
| **All Rooms** | "All Rooms" section | @mentions only | Rooms you monitor casually |
| **Muted** | "All Rooms" section | None | Rooms you're in but don't need alerts |
| **Hidden** | Hidden section | None | Rooms you want out of sight |

### How to Change Involvement

**Quick toggle (bell icon):**
- Click the bell icon next to any room in the sidebar or room header
- **Shared rooms** cycle through: All Rooms → My Rooms → Muted → All Rooms...
- **Direct messages** cycle through: My Rooms (everything) ↔ Muted (nothing)

**Room settings:**
- Open room settings (click room name in header)
- Use "Mute notifications" toggle to silence all alerts
- Use "Hide from sidebar" toggle to move room to hidden section
- Note: "Hide from sidebar" is **not available for Direct Messages** (DMs always appear in the top section)

### Accessing Hidden Rooms

1. Click the `...` menu in the "All Rooms" header
2. Select "Hidden rooms"
3. Hidden rooms are lazy-loaded via Turbo Frames when you click the link
4. Click the eye icon to unhide any room

### Involvement Matrix by Room Type

#### Default Involvement

| Room Type | Default Involvement | Sidebar Location |
|-----------|---------------------|------------------|
| **Open** | `mentions` | All Rooms |
| **Closed** | `mentions` | All Rooms |
| **Direct** | `everything` | Top DM section |
| **Thread** (creator/parent author) | `everything` | Not in sidebar |
| **Thread** (other participants) | `invisible` | Not in sidebar |

#### Available Involvement Levels

| Level | Open | Closed | Direct | Thread |
|-------|:----:|:------:|:------:|:------:|
| `everything` (My Rooms) | ✓ | ✓ | ✓ | ✓ |
| `mentions` (All Rooms) | ✓ | ✓ | ✗ | ✗ |
| `nothing` (Muted) | ✓ | ✓ | ✓ | ✗ |
| `invisible` (Hidden) | ✓ | ✓ | ✗ | ✓ |

#### Bell Icon Cycling (Navbar)

| Room Type | Cycle Order |
|-----------|-------------|
| **Open / Closed** | mentions → everything → nothing → mentions |
| **Direct** | everything ↔ nothing |
| **Thread** | No bell icon shown |

#### Settings Panel Toggles

| Toggle | Open | Closed | Direct | Thread |
|--------|:----:|:------:|:------:|:------:|
| **Mute notifications** | ✓ | ✓ | ✓ | ✗ |
| **Hide from sidebar** | ✓ | ✓ | ✗ | ✗ |

#### Sidebar Visibility

| Room Type | Sidebar Section | Can Be Hidden |
|-----------|-----------------|:-------------:|
| **Open** | My Rooms / All Rooms | ✓ |
| **Closed** | My Rooms / All Rooms | ✓ |
| **Direct** | Top horizontal scroll | ✗ |
| **Thread** | Not shown (use Threads inbox) | N/A |

#### Notification Behavior

| Involvement | Receives Notifications | Sidebar Badge |
|-------------|:----------------------:|:-------------:|
| `everything` | All messages | ✓ |
| `mentions` | @mentions only | ✓ |
| `nothing` | None | ✗ |
| `invisible` | None | N/A (hidden) |

---

## Part 3: Inbox Features

The inbox helps you track important messages across all rooms. Access it from the `...` menu in the "All Rooms" header or the bottom toolbar.

### Mentions

**What it shows:** Messages where you were specifically called out.

**You appear here when:**
- Someone types `@yourname` in a message
- An admin uses `@everyone` in an Open room
- Someone replies to your message (cite/quote)
- You receive any Direct Message

**Key behaviors:**
- Messages from rooms you're not in will auto-add you to that room
- Self-mentions don't appear (you won't see your own @mentions)
- Real-time updates as new mentions arrive

**Unread indicator:** A badge appears on the Mentions icon when you have unread mentions **or unread Direct Messages**.

---

### Notifications

**What it shows:** All messages from rooms where you have "My Rooms" (`everything`) involvement.

**Use case:** See everything happening in rooms you actively follow, without filtering for mentions only.

**Key behaviors:**
- Only shows messages from rooms with `everything` involvement
- Includes all message types (not just mentions)
- Useful for catching up on active discussions

---

### All Messages

**What it shows:** Every message from every room you have access to.

**Use case:** A unified feed of all activity across the workspace.

**Key behaviors:**
- Shows messages from all rooms regardless of involvement level
- Comprehensive view of all workspace activity
- Useful for administrators or catching up after time away

---

### Threads

**What it shows:** Thread conversations you're involved in.

**You appear here when:**
- You created the thread
- Your message was the thread's parent
- You replied in the thread
- The parent room is in your "My Rooms" (everything involvement)

**What's displayed:**
- The original parent message (not individual thread replies)
- Ordered by thread activity (based on `last_active_at`)
- Shows thread preview and reply count

**Key behaviors:**
- Click to jump directly into the thread
- Thread updates appear in real-time

---

### Bookmarks

**What it shows:** Messages you've saved for later.

**How to bookmark:**
- Click the bookmark icon on any message
- A filled bookmark indicator appears on saved messages

**How to remove:**
- Click the bookmark icon again on a bookmarked message
- Or remove from the Bookmarks inbox

**Key behaviors:**
- Only bookmark messages in rooms you can access
- Bookmarks are private (only you see your bookmarks)
- Ordered by when you bookmarked (newest first)

---

### Mark All as Seen

**What it does:** Clears all unread indicators across your inbox.

**How to access:**
- Click the `...` menu in the "All Rooms" header
- Select "Mark all as seen"

**Key behaviors:**
- Marks all mentions, notifications, and messages as read
- Clears unread badges from sidebar rooms
- Confirmation prompt prevents accidental clearing

---

## Part 4: Notifications & Real-Time Updates

### What Triggers Notifications

| Event | Who Gets Notified |
|-------|-------------------|
| New message in room | Members with "My Rooms" involvement |
| @mention | The mentioned user(s) |
| @everyone | All members of Open room |
| DM message | All DM participants |
| Thread reply | Thread participants + "My Rooms" members of parent room |

### Notification Channels

1. **In-app badges:** Red dots on rooms and inbox icons
2. **Browser notifications:** If enabled in your browser
3. **Email digest:** Twice-daily summary of unread mentions (9am and 6pm PT)
   - Only sent to users subscribed to "notifications" in settings
   - Only triggers if at least one unread mention is older than 12 hours
   - Includes unread messages from the past 7 days

### Real-Time Updates

All room and inbox views update instantly via WebSocket connections:
- New messages appear without refreshing
- Involvement changes sync across all your tabs/devices
- Typing indicators show when others are composing

---

## Part 5: Quick Reference

### Sidebar Organization

```
┌─────────────────────────────┐
│  [+ New Ping]  [DM] [DM]... │  ← Direct Messages (horizontal scroll)
├─────────────────────────────┤
│  My Rooms                   │  ← Rooms with "everything" involvement
│    #project-alpha     🔔    │
│    #engineering       🔔    │
├─────────────────────────────┤
│  All Rooms           [+][…] │  ← Rooms with "mentions" involvement
│    #general           🔔    │
│    #random            🔔    │
├─────────────────────────────┤
│  ▶ Hidden Rooms (2)         │  ← Collapsed, click to expand
└─────────────────────────────┘
│  [Mentions] [Threads] [Bookmarks] [Profile] │  ← Bottom toolbar
└─────────────────────────────────────────────┘
```

### Bell Icon States

| Icon | Meaning |
|------|---------|
| 🔔 (filled) | My Rooms - all notifications |
| 🔔@ (with @) | All Rooms - @mentions only |
| 🔕 (slashed) | Muted - no notifications |

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Search messages | `Cmd/Ctrl + K` |
| New message | Focus is automatic in room |
| Navigate rooms | Click or use sidebar |

---

## Part 6: Technical Comparison with Once Campfire

This section compares Campfire-CE with the original Once Campfire (37signals) implementation.

### Room Types

| Feature | Once Campfire | Campfire-CE |
|---------|---------------|-------------|
| Open Rooms | ✅ | ✅ |
| Closed Rooms | ✅ | ✅ |
| Direct Messages | ✅ | ✅ |
| **Thread Rooms** | ❌ | ✅ Added |

**Thread Rooms:** Campfire-CE adds `Rooms::Thread` as a new room type with STI. Threads have:
- `parent_message_id` foreign key linking to origin message
- User-aware `default_involvement()` - thread creator AND parent message author get "everything", others get "invisible"
- All parent room members automatically get thread membership (with invisible involvement by default)
- Automatic involvement upgrade when users reply

### Involvement System

| Feature | Once Campfire | Campfire-CE |
|---------|---------------|-------------|
| Levels | 4 (invisible, nothing, mentions, everything) | 4 (same) |
| Shared room cycling | 4-state full cycle | 3-state (mentions ↔ everything ↔ nothing) |
| Direct room cycling | 2-state (everything ↔ nothing) | 2-state (same) |
| Settings panel toggles | ❌ | ✅ Added |
| Hidden rooms UI | ❌ | ✅ Added |

**Cycling difference:** Once Campfire cycles shared rooms through all 4 states including "invisible". Campfire-CE simplifies to 3 states via the bell icon, with "invisible" only accessible through the Settings panel to prevent accidental hiding.

**Hidden rooms:** Campfire-CE adds a dedicated UI for accessing hidden rooms via the sidebar menu, lazy-loaded via Turbo Frames for better performance.

**DM restrictions:** Direct Messages cannot be hidden from the sidebar - only the "Mute notifications" toggle is available for DMs.

### Involvement Labels

| Level | Once Campfire | Campfire-CE |
|-------|---------------|-------------|
| mentions | "Notifying about @ mentions" | "Room in All Rooms" |
| everything | "Notifying about all messages" | "Room in My Rooms" |
| nothing | "Notifications are off" | "Notifications muted" |
| invisible | "Notifications are off and room invisible" | "Room hidden from sidebar" |

Campfire-CE uses location-focused labels ("My Rooms"/"All Rooms") vs notification-focused labels.

### Inbox Features

| Feature | Once Campfire | Campfire-CE |
|---------|---------------|-------------|
| Mentions tab | ❌ | ✅ Added |
| Notifications tab | ❌ | ✅ Added |
| All Messages tab | ❌ | ✅ Added |
| Threads tab | ❌ | ✅ Added |
| Bookmarks tab | ❌ | ✅ Added |
| Email digest | ❌ | ✅ Added (twice daily) |
| Mark all as seen | ❌ | ✅ Added |

**Inbox system:** Campfire-CE adds a complete inbox system with dedicated pages for mentions, notifications, all messages, threads, and bookmarks. Each has:
- Dedicated query objects (`Inbox::MentionsQuery`, `Inbox::MessagesQuery`, etc.)
- Real-time ActionCable channels
- Cursor-based pagination

### Data Model Additions

**New tables in Campfire-CE:**
- `mentions` - Join table for @mention tracking
- `bookmarks` - User message bookmarks with soft deletion

**New columns:**
- `messages.mentions_everyone` - Boolean for @everyone optimization
- `rooms.parent_message_id` - Thread parent reference

### Broadcasting Differences

| Feature | Once Campfire | Campfire-CE |
|---------|---------------|-------------|
| Room nav updates | Basic | Enhanced with multiple targets |
| Sidebar sections | Single broadcast | Per-section broadcasts (starred, shared) |
| Hidden rooms sync | ❌ | ✅ Real-time add/remove |
| Inbox real-time | ❌ | ✅ Per-feature channels |

**Broadcast count:** Involvement changes in Campfire-CE trigger 2-5 broadcasts depending on visibility transitions, compared to simpler broadcasting in Once Campfire.

### Controller Enhancements

**InvolvementsController additions:**
- `from_sidebar` helper to track update source
- `notifications_ready` action for push notification setup
- `return_to` parameter for Settings panel redirects
- Turbo Stream response handling (`head :ok` for AJAX)

### Query Objects

Campfire-CE extracts complex queries into dedicated objects:

```
app/models/inbox/
├── mentions_query.rb    # User's mentioning messages
├── threads_query.rb     # User's thread involvement
├── bookmarks_query.rb   # User's bookmarked messages
└── messages_query.rb    # General message queries

app/models/
└── sidebar_memberships.rb  # Sidebar room filtering
```

### API Additions

**Bot DM API:** Campfire-CE adds `Rooms::Directs::ByBotsController` for bot-initiated DMs:
- `POST /rooms/:bot_key/directs` - Create DM as bot
- Returns `201 Created` for new rooms, `200 OK` for existing
- JSON error handling with `rescue_from Exception`

### Summary

Campfire-CE extends Once Campfire with:
1. **Thread rooms** for focused side conversations
2. **Inbox system** for tracking mentions, threads, and bookmarks
3. **Enhanced involvement UI** with Settings panel and hidden rooms
4. **Simplified cycling** to prevent accidental room hiding
5. **Real-time broadcasting** for all new features
6. **Bot API** for DM creation

The core architecture remains compatible, with additions building on Rails conventions and the existing STI room system.

---

## Part 7: Technical Architecture

This section provides a deep dive into how rooms and inbox features are built.

### Room System Architecture

#### Single Table Inheritance (STI)

All room types share a single `rooms` table with a `type` column for polymorphism:

```
rooms table:
├── id
├── type          # "Rooms::Open", "Rooms::Closed", "Rooms::Direct", "Rooms::Thread"
├── name
├── slug          # URL-friendly identifier (optional)
├── creator_id    # User who created the room
├── parent_message_id  # For threads only
├── messages_count     # Counter cache
├── last_active_at     # For sorting
├── active        # Soft deletion flag
└── timestamps
```

#### Class Hierarchy

```
Room (base class)
├── Rooms::Open      # Public rooms
├── Rooms::Closed    # Private rooms
├── Rooms::Direct    # DMs
└── Rooms::Thread    # Thread conversations
```

#### Base Room Model

**File:** `app/models/room.rb`

```ruby
class Room < ApplicationRecord
  include Deactivatable

  # Associations with scopes
  has_many :memberships, -> { active }
  has_many :users, -> { active }, through: :memberships
  has_many :messages, -> { active }
  has_many :threads, through: :messages, class_name: "Rooms::Thread"

  belongs_to :creator, class_name: "User"
  belongs_to :parent_message, optional: true  # For threads

  # Key methods
  def default_involvement(user: nil)
    "mentions"  # Overridden by subclasses
  end

  def display_name(for_user: nil)
    # Returns appropriate name based on room type
  end
end
```

---

### Rooms::Open Architecture

**File:** `app/models/rooms/open.rb`

**Purpose:** Public rooms accessible to all workspace members.

**Key behavior:**
```ruby
class Rooms::Open < Room
  after_save_commit :grant_access_to_all_users

  private
    def grant_access_to_all_users
      return unless type_previously_changed?(to: "Rooms::Open")

      users_to_add = User.active
        .joins("LEFT JOIN memberships ON ...")
        .where("memberships.id IS NULL")

      memberships.grant_to(users_to_add) if users_to_add.exists?
    end
end
```

**Auto-membership:** When a room becomes Open (created or converted), users not already members are automatically granted membership. The callback only fires when the type changes to "Rooms::Open", preventing redundant operations on every save.

**Controller:** `app/controllers/rooms/opens_controller.rb`
- `new` / `create` - Room creation with broadcast to all users
- `edit` / `update` - Name/slug changes
- `destroy` - Soft deletion

**Views:**
```
app/views/rooms/opens/
├── new.html.erb     # Creation form
└── edit.html.erb    # Uses shared layout
```

---

### Rooms::Closed Architecture

**File:** `app/models/rooms/closed.rb`

**Purpose:** Private rooms with explicit membership.

**Key behavior:**
```ruby
class Rooms::Closed < Room
  # No auto-membership - users must be explicitly added
end
```

**Controller:** `app/controllers/rooms/closeds_controller.rb`
- `create` - Creates room with selected users
- `update` - Can revise membership (grant/revoke users)

**Membership management:**
```ruby
def update
  @room.memberships.revise(
    granted: users_to_add,
    revoked: users_to_remove
  )
end
```

**Views:**
```
app/views/rooms/closeds/
├── new.html.erb     # User selection UI
└── edit.html.erb    # Member management
```

---

### Rooms::Direct Architecture

**File:** `app/models/rooms/direct.rb`

**Purpose:** Private conversations between specific users.

**Singleton pattern:**
```ruby
class Rooms::Direct < Room
  def self.find_or_create_for(users)
    find_for(users) || create_for({}, users: users)
  end

  def default_involvement(user: nil)
    "everything"  # DM participants get all notifications
  end

  private
    def self.find_for(users)
      # Finds existing room with exact same user set
      all.joins(:users).detect do |room|
        Set.new(room.user_ids) == Set.new(users.pluck(:id))
      end
    end
end
```

**Key characteristics:**
- Same user set always returns same room (idempotent)
- Default involvement is "everything" (all messages notify)
- Display name shows other participants' names

**Controller:** `app/controllers/rooms/directs_controller.rb`
```ruby
def create
  @room = Rooms::Direct.find_or_create_for(selected_users)
  broadcast_create_room(@room)
  redirect_to room_url(@room)
end
```

**Bot API:** `app/controllers/rooms/directs/by_bots_controller.rb`
```ruby
class Rooms::Directs::ByBotsController < Rooms::DirectsController
  allow_bot_access only: :create

  def create
    create_room
    render json: { room: { id: @room.id } },
           status: (@room.previously_new_record? ? :created : :ok)
  end
end
```

---

### Rooms::Thread Architecture

**File:** `app/models/rooms/thread.rb`

**Purpose:** Side conversations attached to a parent message.

```ruby
class Rooms::Thread < Room
  validates_presence_of :parent_message

  def default_involvement(user: nil)
    if user.present? && (user == creator || user == parent_message&.creator)
      "everything"  # Creators see all
    else
      "invisible"   # Others don't see in sidebar
    end
  end
end
```

**Key characteristics:**
- Requires `parent_message_id` foreign key
- User-aware default involvement
- Not shown in sidebar (appears in Threads inbox)

**Controller:** `app/controllers/rooms/threads_controller.rb`
```ruby
def new
  @room = find_or_create_thread
  grant_access_to_parent_room_members
  redirect_to room_url(@room)
end

private
  def find_or_create_thread
    existing = Rooms::Thread.find_by(parent_message: @message)
    existing || Rooms::Thread.create!(parent_message: @message, creator: Current.user)
  end
```

**Display name:**
```ruby
def display_name(for_user: nil)
  "🧵 #{parent_message&.room&.name}"
end
```

---

### Membership Architecture

**File:** `app/models/membership.rb`

**Schema:**
```
memberships table:
├── id
├── room_id
├── user_id
├── involvement    # enum: invisible, nothing, mentions, everything
├── unread_at      # Timestamp of first unread message
├── connected_at   # WebSocket connection tracking
├── connections    # Connection count
├── active         # Soft deletion
└── timestamps
```

**Involvement enum:**
```ruby
enum :involvement,
     %w[invisible nothing mentions everything].index_by(&:itself),
     prefix: :involved_in

# Generates: involved_in_invisible?, involved_in_nothing?, etc.
```

**Key scopes:**
```ruby
scope :visible, -> { where.not(involvement: :invisible) }
scope :notifications_on, -> { where(involvement: :everything) }
```

**Membership extensions on Room:**
```ruby
has_many :memberships, -> { active } do
  def grant_to(users)
    # Bulk upsert memberships
  end

  def revoke_from(users)
    # Soft delete memberships
  end

  def revise(granted:, revoked:)
    # Atomic grant + revoke
  end
end
```

---

### Involvement Controller Architecture

**File:** `app/controllers/rooms/involvements_controller.rb`

```ruby
class Rooms::InvolvementsController < ApplicationController
  include RoomScoped  # Sets @room and @membership

  def update
    @membership.update!(involvement: params[:involvement])
    broadcast_involvement_changes
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to return_path }
    end
  end

  private
    def broadcast_involvement_changes
      broadcast_involvement_change_to_room_nav
      broadcast_involvement_change_to_sidebar
      add_or_remove_rooms_in_sidebar
    end
end
```

**Broadcast targets:**
1. Room navigation (bell icon in header)
2. Sidebar room rows (both starred and shared sections)
3. Hidden rooms section (on visibility transitions)

**Helper cycling logic:**

**File:** `app/helpers/rooms/involvements_helper.rb`

```ruby
SHARED_INVOLVEMENT_ORDER = %w[mentions everything nothing]
DIRECT_INVOLVEMENT_ORDER = %w[everything nothing]

def next_involvement_for(room, involvement:)
  order = room.direct? ? DIRECT_INVOLVEMENT_ORDER : SHARED_INVOLVEMENT_ORDER
  order[(order.index(involvement) || 0) + 1] || order.first
end
```

---

### Inbox Architecture Overview

```
app/controllers/
├── inboxes_controller.rb        # Base inbox with mentions, notifications, messages, threads, bookmarks, clear actions
└── inboxes/
    ├── mentions_controller.rb   # Dedicated mentions (alternative entry point)
    ├── notifications_controller.rb  # Messages from "everything" involvement rooms
    ├── messages_controller.rb   # All messages across all rooms
    ├── threads_controller.rb    # Thread inbox
    └── bookmarks_controller.rb  # Bookmarks inbox

app/models/inbox/
├── mentions_query.rb    # @mention queries
├── threads_query.rb     # Thread involvement queries
├── bookmarks_query.rb   # Bookmark queries
└── messages_query.rb    # Shared message queries (used by notifications + all messages)

app/views/inboxes/
├── show.html.erb        # Main inbox redirect
├── mentions.html.erb    # Mentions page
├── notifications.html.erb   # Notifications page
├── messages.html.erb    # All messages page
├── threads.html.erb     # Threads page
└── bookmarks.html.erb   # Bookmarks page
```

---

### Mentions Architecture

**Data model:**

**File:** `app/models/mention.rb`
```ruby
class Mention < ApplicationRecord
  belongs_to :message
  belongs_to :user

  # Table has no primary key (id: false), uses unique index on (message_id, user_id)
end
```

**Mention creation:**

**File:** `app/models/message/mentionee.rb`
```ruby
module Message::Mentionee
  extend ActiveSupport::Concern

  included do
    has_many :mentions, dependent: :destroy
    after_save :create_mentionees  # Note: after_save, not after_create_commit
  end

  def mentionees
    if mentions_everyone?
      room.users
    elsif persisted?
      mentioned_users_association
    else
      # For unsaved messages, parse the body directly
      mentioned_users.select { |user| room.user_ids.include?(user.id) }
    end
  end

  private
    def create_mentionees
      if mentions_everyone_in_body?
        update_column(:mentions_everyone, true)
      else
        sync_mentions_with(mentioned_users)
      end
    end
end
```

**Query object:**

**File:** `app/models/inbox/mentions_query.rb`
```ruby
class Inbox::MentionsQuery
  def initialize(user)
    @user = user
  end

  def call
    user.mentioning_messages
        .without_created_by(user)
        .with_threads
        .with_creator
  end

  private

  attr_reader :user
end
```

**ActionCable channel:**

**File:** `app/channels/inbox_mentions_channel.rb`
```ruby
class InboxMentionsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_mentions  # Uses stream_for, not stream_from
  end
end
```

**Broadcasting:**

**File:** `app/models/message/broadcasts.rb`
```ruby
def broadcast_to_inbox_mentions
  return if mentionee_ids.blank?
  return if mentions_everyone?

  mentionees.each do |user|
    next if user.id == creator_id  # Skip self-mentions

    broadcast_remove_to user, :inbox_mentions,
                       target: ActionView::RecordIdentifier.dom_id(self)

    broadcast_append_to user, :inbox_mentions,
                        target: "inbox",  # Note: targets "inbox", not "inbox_mentions"
                        partial: "messages/message",
                        locals: { message: self, timestamp_style: :long_datetime }
  end
end
```

---

### Threads Inbox Architecture

**Query object:**

**File:** `app/models/inbox/threads_query.rb`
```ruby
class Inbox::ThreadsQuery
  def initialize(user)
    @user = user
  end

  def call
    Message.active
           .joins(:room)
           .where.not(rooms: { type: "Rooms::Thread" })
           .where(id: accessible_thread_parent_ids)
           .with_threads
           .with_creator
           .order(thread_activity_order)
  end

  private

  attr_reader :user

  def accessible_thread_parent_ids
    Room.active
        .where(id: all_accessible_thread_ids, type: "Rooms::Thread")
        .where("messages_count > 0")
        .pluck(:parent_message_id)
  end

  # Combines explicit thread memberships with implicit access via parent room "everything" involvement
  def all_accessible_thread_ids
    thread_ids_from_memberships | thread_ids_from_parent_rooms
  end

  def thread_ids_from_memberships
    user.memberships.active.visible
        .joins(:room)
        .where(rooms: { type: "Rooms::Thread" })
        .pluck(:room_id)
  end

  def thread_ids_from_parent_rooms
    Room.where(type: "Rooms::Thread")
        .joins(:parent_message)
        .where(messages: { room_id: parent_room_ids_with_everything_involvement })
        .pluck(:id)
  end
end
```

**Key insight:** Users see threads either through:
1. Explicit thread membership (replied in thread)
2. Implicit access via "everything" involvement in parent room

**ActionCable channel:**

**File:** `app/channels/inbox_threads_channel.rb`
```ruby
class InboxThreadsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "user_#{current_user.id}_inbox_threads"
  end
end
```

---

### Bookmarks Architecture

**Data model:**

**File:** `app/models/bookmark.rb`
```ruby
class Bookmark < ApplicationRecord
  include Deactivatable, Pagination

  belongs_to :message
  belongs_to :user
end
```

**Controller:**

**File:** `app/controllers/messages/bookmarks_controller.rb`
```ruby
class Messages::BookmarksController < ApplicationController
  before_action :set_message

  def create
    @bookmark = @message.bookmarks.find_or_create_by(user: Current.user)
    broadcast_bookmark_update
  end

  def destroy
    Current.user.bookmarks.where(message: @message).find_each(&:deactivate!)
    broadcast_bookmark_removal
  end
end
```

**Bookmark status injection:**

**File:** `app/models/bookmark.rb`
```ruby
def self.with_bookmark_status(messages, user: Current.user)
  bookmarked_ids = user.bookmarks.where(message: messages).pluck(:message_id)
  messages.each { |m| m.bookmarked = bookmarked_ids.include?(m.id) }
end
```

**Query object:**

**File:** `app/models/inbox/bookmarks_query.rb`
```ruby
class Inbox::BookmarksQuery
  def initialize(user)
    @user = user
  end

  def call
    user.bookmarks
        .joins(:message)
        .includes(message: [ :creator, :threads ])
        .merge(Message.active.with_threads.with_creator)
  end

  private

  attr_reader :user
end
```

---

### Real-Time Architecture

#### ActionCable Channels

```
app/channels/
├── application_cable/
│   ├── connection.rb     # Authentication via session
│   └── channel.rb        # Base channel
├── room_channel.rb       # Message streaming per room
├── presence_channel.rb   # Online user tracking
├── room_list_channel.rb  # Sidebar updates
├── unread_rooms_channel.rb
├── typing_notifications_channel.rb
├── inbox_mentions_channel.rb
├── inbox_threads_channel.rb
└── inbox_bookmarks_channel.rb
```

#### Turbo Streams Broadcasting

**Pattern used throughout:**
```ruby
# In controller or model
broadcast_append_to [user, :stream_name],
  target: "dom_element_id",
  partial: "path/to/partial",
  locals: { ... }

# In view (subscription)
<%= turbo_stream_from Current.user, :stream_name %>
```

#### Broadcast Helpers

**File:** `app/controllers/concerns/sidebar.rb`
```ruby
module Sidebar
  def for_each_sidebar_section
    [:starred_rooms, :shared_rooms].each { |name| yield name }
  end

  def broadcast_replace_to(...)
    Turbo::StreamsChannel.broadcast_replace_to(...)
  end

  def broadcast_append_to(...)
    Turbo::StreamsChannel.broadcast_append_to(...)
  end

  def broadcast_remove_to(...)
    Turbo::StreamsChannel.broadcast_remove_to(...)
  end
end
```

---

### Sidebar Architecture

**Query object:**

**File:** `app/models/sidebar_memberships.rb`
```ruby
class SidebarMemberships
  def initialize(user)
    @user = user
  end

  def direct
    user.memberships.visible.direct_rooms
      .recently_active_or_unread
      .with_room_by_last_active_newest_first
  end

  def shared
    user.memberships.visible
      .without_direct_rooms
      .without_thread_rooms
      .with_has_unread_notifications
  end

  def hidden
    user.memberships
      .where(involvement: :invisible)
      .without_thread_rooms
  end
end
```

**Controller:**

**File:** `app/controllers/users/sidebars_controller.rb`
```ruby
class Users::SidebarsController < ApplicationController
  include Sidebar  # From app/controllers/concerns/sidebar.rb

  before_action :set_sidebar_memberships

  def show ; end
end
```

**File:** `app/controllers/concerns/sidebar.rb`
```ruby
module Sidebar
  def set_sidebar_memberships
    sidebar = SidebarMemberships.new(Current.user)
    @direct_memberships  = sidebar.direct
    @direct_room_members = sidebar.direct_room_members(@direct_memberships)
    @shared_memberships  = sidebar.shared
    @hidden_memberships  = sidebar.hidden
  end
end
```

**View structure:**
```
app/views/users/sidebars/
├── show.html.erb              # Main sidebar
├── _all_rooms_actions.html.erb # Menu with hidden rooms option
└── rooms/
    ├── _direct.html.erb       # DM row
    ├── _shared.html.erb       # Room row with bell
    ├── _hidden.html.erb       # Hidden room with unhide button
    └── _shared_rooms_list.html.erb
```

---

### File Structure Summary

```
app/
├── models/
│   ├── room.rb                    # Base room class
│   ├── rooms/
│   │   ├── open.rb                # Public rooms
│   │   ├── closed.rb              # Private rooms
│   │   ├── direct.rb              # DMs
│   │   └── thread.rb              # Threads
│   ├── membership.rb              # Room membership
│   ├── mention.rb                 # @mention tracking
│   ├── bookmark.rb                # Message bookmarks
│   ├── message.rb                 # Chat messages
│   ├── message/
│   │   ├── mentionee.rb           # Mention extraction
│   │   └── broadcasts.rb          # Real-time updates
│   ├── inbox/
│   │   ├── mentions_query.rb
│   │   ├── threads_query.rb
│   │   └── bookmarks_query.rb
│   └── sidebar_memberships.rb
├── controllers/
│   ├── rooms_controller.rb        # Base room controller
│   ├── rooms/
│   │   ├── opens_controller.rb
│   │   ├── closeds_controller.rb
│   │   ├── directs_controller.rb
│   │   ├── directs/
│   │   │   └── by_bots_controller.rb
│   │   ├── threads_controller.rb
│   │   ├── involvements_controller.rb
│   │   └── merges_controller.rb
│   ├── inboxes_controller.rb
│   ├── inboxes/
│   │   ├── mentions_controller.rb
│   │   ├── threads_controller.rb
│   │   ├── bookmarks_controller.rb
│   │   ├── messages_controller.rb
│   │   └── notifications_controller.rb
│   ├── messages_controller.rb
│   └── messages/
│       └── bookmarks_controller.rb
├── helpers/
│   └── rooms/
│       └── involvements_helper.rb  # Cycling logic
├── channels/
│   ├── room_channel.rb
│   ├── inbox_mentions_channel.rb
│   ├── inbox_threads_channel.rb
│   └── inbox_bookmarks_channel.rb
└── views/
    ├── rooms/
    │   ├── show/
    │   ├── opens/
    │   ├── closeds/
    │   ├── directs/
    │   ├── threads/
    │   ├── involvements/
    │   └── layouts/
    │       ├── _form.html.erb
    │       └── _involvement_settings.html.erb
    ├── inboxes/
    │   ├── mentions.html.erb
    │   ├── threads.html.erb
    │   └── bookmarks.html.erb
    └── users/
        └── sidebars/
```

---

### Request Flow Examples

#### Creating a Message with @mention

```
1. User submits message form
   POST /rooms/:id/messages

2. MessagesController#create
   → Message.create!(body: ...)

3. Message after_create_commit callbacks:
   → sync_mentions (creates Mention records)
   → involve_mentionees_in_room (adds users to room)
   → broadcast_to_room (Turbo Stream append)
   → broadcast_to_inbox_mentions (per-user append)

4. ActionCable delivers to:
   → RoomChannel subscribers (room view)
   → InboxMentionsChannel subscribers (mentions inbox)
```

#### Changing Room Involvement

```
1. User clicks bell icon
   PUT /rooms/:id/involvement?involvement=everything

2. InvolvementsController#update
   → @membership.update!(involvement: ...)
   → broadcast_involvement_changes

3. Broadcasts:
   → Replace bell in room nav
   → Replace room row in starred_rooms section
   → Replace room row in shared_rooms section
   → (If visibility changed) Add/remove from hidden section

4. ActionCable delivers to user's sidebar
```

#### Opening Threads Inbox

```
1. User clicks Threads icon
   GET /inbox/threads

2. Inboxes::ThreadsController#index
   → Inbox::ThreadsQuery.new(Current.user).call

3. Query combines:
   → Thread memberships (explicit)
   → Parent room "everything" involvement (implicit)

4. Returns parent messages with thread metadata
   → Ordered by thread.last_active_at DESC
```

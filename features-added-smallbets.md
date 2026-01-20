# Features Added from Small Bets Fork

This document tracks features ported from the [Small Bets](https://smallbets.com) Campfire fork into Campfire-CE. Each feature includes implementation status and key file locations.

---

## Implemented Features

### Mentions Tab
Members can see all their @mentions from a dedicated inbox view in the sidebar.

**Key files:**
- `app/controllers/inboxes_controller.rb` - `mentions` action
- `app/models/user.rb:36-42` - `mentioning_messages` query
- `app/views/inboxes/mentions.html.erb`

---

### Email Notifications
Daily email digest for unread mentions and direct messages, sent at 9am and 6pm PT.

**Key files:**
- `app/jobs/unread_mentions_notifier_job.rb`
- `app/mailers/mention_mailer.rb`
- `config/recurring.yml` - scheduled job configuration

---

### User Counter
Shows how many members have been recently active (last 24 hours) in a room.

**Key files:**
- `app/helpers/rooms_helper.rb` - `member_count` helper
- `app/views/rooms/_header.html.erb`

---

### New Since Last Visit
A separator line appears between old messages and new ones, similar to Hey's Feed feature.

**Key files:**
- `app/views/messages/_message.html.erb` - `message__new-separator` element
- `app/models/membership.rb` - `unread_at` timestamp tracking

---

### Mark Messages as Unread
Members can mark any message as unread to resurface it later.

**Key files:**
- `app/controllers/messages/unreads_controller.rb`
- `app/models/membership.rb:97-100` - `mark_unread_at` method

---

### Email-Based Auth (OTP)
Passwordless login via 6-digit codes sent to email.

**Key files:**
- `app/models/auth_token.rb` - token generation and validation
- `app/controllers/auth_tokens_controller.rb`
- `app/mailers/auth_mailer.rb`
- `db/migrate/20240910115400_create_auth_tokens.rb`

---

### Bookmarks
Members can bookmark messages for later reference, accessible from a dedicated inbox tab.

**Key files:**
- `app/models/bookmark.rb`
- `app/controllers/messages/bookmarks_controller.rb`
- `app/controllers/inboxes_controller.rb` - `bookmarks` action
- `db/migrate/20240525122726_create_bookmarks.rb`

---

### One-Click Reboost
Members can quickly repeat someone else's boost by clicking on it.

**Key files:**
- `app/frontend/controllers/boost_repeat_controller.js`
- `app/controllers/boosts_controller.rb`

---

### Mentions List Relevance
The @mention autocomplete ranks users by recency of their last message, making it easier to find active members.

**Key files:**
- `app/models/user.rb` - `recent_posters_first` scope
- `app/controllers/autocompletable/users_controller.rb:17` - applies `recent_posters_first`

---

### Replies as Mentions
Thread replies trigger mention-style notifications for thread participants.

**Key files:**
- `app/models/message/broadcasts.rb:74-113` - `broadcast_to_inbox_threads`
- `app/channels/inbox_threads_channel.rb`

---

### Maintain Scrollbar Position
Sidebar scroll position is preserved when switching between rooms.

**Key files:**
- `app/frontend/controllers/maintain_scroll_controller.js`
- `app/models/room.rb` - broadcasts with `maintain_scroll: true`

---

### Threads
Threaded discussions tied to a parent message. Threads are special rooms that can be archived after inactivity.

**Key files:**
- `app/models/rooms/thread.rb` - STI subclass
- `app/controllers/rooms/threads_controller.rb`
- `app/views/messages/_threads.html.erb`
- `db/migrate/20240328093042_add_parent_message_to_rooms.rb`

---

### Block Pings
Members can block other users from sending them direct messages. Admins can monitor blocked users.

**Key files:**
- `app/models/block.rb`
- `app/controllers/blocks_controller.rb`
- `app/models/user.rb` - `blocked_in?` method
- `db/migrate/20250804105525_create_blocks.rb`

---

### Stats Page
Community leaderboards and analytics with daily, monthly, yearly, and all-time views.

**Key files:**
- `app/controllers/stats_controller.rb`
- `app/controllers/rooms/stats_controller.rb`
- `app/models/stats_service.rb`
- `app/views/stats/` - multiple view templates

---

### Rich-Text on Mobile
Rich text formatting options available on mobile devices.

**Key files:**
- `app/frontend/controllers/composer_controller.js`
- Mobile-responsive Trix editor styling

---

### Soft Deletion
Records are marked inactive rather than destroyed, preventing data loss from untrusted members.

**Key files:**
- `app/models/concerns/deactivatable.rb` - shared concern
- Applied to: `Message`, `Bookmark`, `Boost`, `Membership`, `Room`, `Account`
- `db/migrate/20241015185047_add_active_to_boosts.rb`

---

### Bot API Extras
Enhanced webhook system for bots, including an "everything webhook" that receives all events.

**Key files:**
- `app/models/webhook.rb`
- `app/models/webhook_event.rb`
- `app/controllers/rooms/directs/by_bots_controller.rb` - bot-initiated DMs
- `app/models/user/bot.rb`

---

### Enhanced Inbox System
Multiple inbox tabs: mentions, threads, notifications, messages, and bookmarks.

**Key files:**
- `app/controllers/inboxes_controller.rb` - all inbox actions
- `app/views/inboxes/` - tab views
- `app/views/users/sidebars/_inbox_tabs.html.erb`

---

### @everyone Mention
Admins can notify all members in an open room with a single @everyone mention.

**Key files:**
- `app/models/everyone.rb` - stub object for GlobalID
- `app/models/message.rb:156-167` - validation (admin + open room only)
- `app/models/message/mentionee.rb:44-52` - sets `mentions_everyone` flag
- `app/controllers/autocompletable/users_controller.rb:20-30` - shows in autocomplete for admins
- `app/views/everyone/_mention.html.erb`
- `db/migrate/20251021014520_add_mentions_everyone_to_messages.rb`

---

### Room Search
Filter rooms by typing in a search input at the top of the room list.

**Key files:**
- `app/models/search.rb`
- `app/controllers/searches_controller.rb`
- `app/frontend/controllers/search_controller.js`

---

### My Rooms / Sidebar Organization
Organized sidebar with room lists and membership-based filtering.

**Key files:**
- `app/models/sidebar_memberships.rb` - query object
- `app/controllers/users/sidebars_controller.rb`
- `app/views/users/sidebars/`

---

### Marketing Page
Public landing page for unauthenticated visitors with community stats.

**Key files:**
- `app/controllers/marketing_controller.rb`
- `app/views/marketing/show.html.erb`

---

## Removed Features

These features were in the Small Bets fork but have been removed from Campfire-CE:

- **Experts Directory** - Page showing resident experts and their areas of expertise
- **Video Library** - React-based video content library with Vimeo integration
- **Live Events Banner** - Countdown banner for upcoming webinars/AMAs

---

## Features Not Yet Ported

These features from the Small Bets documentation have unclear or partial implementation:

| Feature | Notes |
|---------|-------|
| Hide empty pings | Not showing empty direct rooms in sidebar - not found |
| Updated names cache | Cache cleanup on name change - not explicitly found |
| Boost speed optimization | Consolidated roundtrips - implementation details unclear |

---

## Architecture Notes

The Small Bets features use several common patterns:

1. **Single Table Inheritance (STI)** for room types: `Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`, `Rooms::Thread`

2. **Soft deletion** via `Deactivatable` concern with `active` boolean and `active` scope

3. **Query objects** for complex queries (e.g., `SidebarMemberships`)

4. **Turbo Streams** for real-time updates via ActionCable

5. **Stimulus controllers** for frontend interactivity

---

## References

- Original modifications document: `smallbets-mods.md`
- Small Bets GitHub commits linked in `smallbets-mods.md`

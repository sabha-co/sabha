# Plan: Rename "Mentions" to "Activity" (Slack-style)

> **⚠️ Superseded:** This plan has been superseded by [split-activity-and-dms.md](split-activity-and-dms.md).
> Activity no longer includes DMs - they now have their own separate inbox view.

## Summary

Rename the "Mentions" inbox tab to "Activity" to better reflect its contents (DMs + @mentions + @everyone), aligning with Slack's terminology. Also fix the bug where DMs can't be cleared from the mark-as-read button.

## Status: Completed (then superseded)

## Bug Fix Detail

The mark-as-read button on the Mentions page couldn't clear DMs because the old `mark_mentions_as_read` method checked for "non-mention messages" in all rooms. Since DMs don't have @mentions (they're just regular messages), the check `non_mentions.none?` was always `false` for DMs, preventing them from being marked as read.

**Fix:** In `mark_activity_as_read`, DMs (`Rooms::Direct`) are now always marked as read since all DM messages are "activity" by definition.

## Files Changed

### Renamed/Created
- `app/models/inbox/mentions_query.rb` → `app/models/inbox/activity_query.rb`
- `app/channels/inbox_mentions_channel.rb` → `app/channels/inbox_activity_channel.rb`
- `app/controllers/inboxes/mentions_controller.rb` → `app/controllers/inboxes/activity_controller.rb`
- `app/views/inboxes/mentions.html.erb` → `app/views/inboxes/activity.html.erb`
- `app/frontend/controllers/mentions_indicator_controller.js` → `app/frontend/controllers/activity_indicator_controller.js`

### Modified

#### Routes
**`config/routes.rb`**
- `get :mentions` → `get :activity`
- `resources :mentions` → `resources :activity` (paged)
- Route helpers: `mentions_inbox_path` → `activity_inbox_path`

#### Controllers
**`app/controllers/inboxes_controller.rb`**
- Renamed `mentions` action → `activity`
- Updated `show` redirect: `mentions_inbox_path` → `activity_inbox_path`
- Updated `clear` action: `scope: "mentions"` → `scope: "activity"`
- Renamed session key: `inbox_last_loaded_mention_created_at` → `inbox_last_loaded_activity_created_at`

#### Models
**`app/models/user.rb`**
- Renamed `mark_mentions_as_read` → `mark_activity_as_read`
- Fixed bug: DMs are now always marked as read (no non-mention check needed)

**`app/models/message/broadcasts.rb`**
- Renamed `broadcast_to_inbox_mentions` → `broadcast_to_inbox_activity`
- Updated stream name: `:inbox_mentions` → `:inbox_activity`

#### Views
**`app/views/inboxes/activity.html.erb`**
- Updated page title: "Mentions" → "Activity"
- Updated nav title: "Mentions" → "Activity"
- Updated clear button scope: `"mentions"` → `"activity"`
- Updated turbo stream: `:inbox_mentions` → `:inbox_activity`
- Updated cache key

**`app/views/inboxes/show.html.erb`**
- Updated empty state: "No mentions yet" → "No activity yet"
- Updated description to include DMs

**`app/views/users/sidebars/show.html.erb`**
- Updated controller: `mentions-indicator` → `activity-indicator`
- Updated data target: `mentions_indicator_target` → `activity_indicator_target`
- Updated label: "Mentions" → "Activity"

**`app/views/users/sidebars/_inbox_actions.html.erb`**
- Updated link: `mentions_inbox_path` → `activity_inbox_path`
- Updated label: "Mentions" → "Activity"

**`app/views/users/sidebars/_all_rooms_actions.html.erb`**
- Same changes as above

#### JavaScript & CSS
**`app/frontend/controllers/activity_indicator_controller.js`**
- Updated CSS class: `has-unread-mentions` → `has-unread-activity`

**`app/assets/stylesheets/application/sidebar.css`**
- Renamed `.has-unread-mentions` → `.has-unread-activity`

#### Tests
**`test/controllers/inboxes_controller_test.rb`**
- Updated all `mentions_inbox_url` → `activity_inbox_url`
- Updated test names and assertions
- Updated `scope: "mentions"` → `scope: "activity"`

**`test/controllers/inboxes/paged_controllers_test.rb`**
- Updated `paged_inbox_mentions_url` → `paged_inbox_activity_index_url`

## NOT Changed (Out of Scope)
- `UnreadMentionsNotifierJob` - Email digest is specifically about @mentions
- `app/views/notifier_mailer/unread_mentions.*` - Keep as-is
- `app/assets/images/mentions.svg` - Keep icon file name
- `docs/ROOMS_AND_INBOX_GUIDE.md` - Documentation update deferred

## Bug: DMs Not Cleared by Mark-as-Read Button

### Problem
When clicking the "Mark as read" button on the Mentions (now Activity) page, DMs were not being marked as read.

### Root Cause
The old `mark_mentions_as_read` method in `app/models/user.rb` had this logic:

```ruby
def mark_mentions_as_read(loaded_at)
  mentions_until = freshness_checked_time(loaded_at)

  memberships.unread.with_has_unread_notifications.each do |m|
    next unless m.has_unread_notifications?

    non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, mentions_until)
    m.read_until(mentions_until) if non_mentions.none?
  end
end
```

The issue: For DMs (`Rooms::Direct`), the `without_user_mentions` query returns *all* messages because DMs don't have @mentions - they're just regular messages. So `non_mentions.none?` was always `false` for DMs, and they were never marked as read.

### Solution
Updated the method to handle DMs as a special case:

```ruby
def mark_activity_as_read(loaded_at)
  activity_until = freshness_checked_time(loaded_at)

  memberships.unread.with_has_unread_notifications.each do |m|
    next unless m.has_unread_notifications?

    # DMs are always "activity" - no need to check for non-mentions
    if m.room.is_a?(Rooms::Direct)
      m.read_until(activity_until)
    else
      non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, activity_until)
      m.read_until(activity_until) if non_mentions.none?
    end
  end
end
```

DMs are now always marked as read since all DM messages are "activity" by definition. For other rooms, the original logic is preserved to avoid accidentally marking rooms as read when they have unread non-mention messages.

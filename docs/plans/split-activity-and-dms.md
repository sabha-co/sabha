# Plan: Split Activity and DMs into Separate Inbox Views

## Summary

Separate the current Activity inbox into two distinct views:
1. **Activity** - @mentions and @everyone only (no DMs)
2. **DMs** - Full DM inbox showing conversation list chronologically

DMs will remain visible in the top sidebar row (horizontal scroll) AND be accessible via a new DMs inbox button.

## Implementation Status: ✅ Complete

All planned features have been implemented. This document now reflects the actual implementation.

## Files Modified/Created

### 1. Models

**`app/models/inbox/activity_query.rb`** - Excludes DMs
```ruby
def call
  user.mentioning_messages
      .without_created_by(user)
      .joins(:room)
      .where.not(rooms: { type: "Rooms::Direct" })  # Exclude DMs
      .with_thread_summary
      .with_creator
end
```

**`app/models/inbox/direct_messages_query.rb`** - NEW FILE
```ruby
class Inbox::DirectMessagesQuery
  def initialize(user)
    @user = user
  end

  def call
    user.memberships
        .visible
        .direct_rooms
        .joins(:room)
        .merge(Room.active)
        .with_has_unread_notifications
        .includes(room: [
          { memberships: { user: { avatar_attachment: { blob: :variant_records } } } },
          { last_message: [ :rich_text_body, { creator: { avatar_attachment: { blob: :variant_records } } } ] }
        ])
        .order("rooms.last_active_at DESC")
  end

  private
  attr_reader :user
end
```

**`app/models/rooms/direct.rb`** - Added batch member loading
```ruby
# Returns users in this DM room excluding the given user, with avatars eager loaded
def members_for_display(excluding:)
  memberships.active
    .includes(user: { avatar_attachment: { blob: :variant_records } })
    .map(&:user)
    .reject { |u| u.id == excluding.id }
end

# Batch load members for multiple rooms, returning { room_id => [users] }
def self.members_for_display_by_room(room_ids, excluding:)
  return {} if room_ids.empty?

  Membership.active
    .where(room_id: room_ids)
    .includes(user: { avatar_attachment: { blob: :variant_records } })
    .group_by(&:room_id)
    .transform_values { |ms| ms.map(&:user).reject { |u| u.id == excluding.id } }
end
```

**`app/models/user.rb`** - Updated mark as read methods
```ruby
# Marks only rooms with unread activity (@mentions) as read.
# DMs are handled separately by mark_direct_messages_as_read.
def mark_activity_as_read(loaded_at)
  activity_until = freshness_checked_time(loaded_at)

  memberships.unread.with_has_unread_notifications.each do |m|
    next unless m.has_unread_notifications?
    next if m.room.is_a?(Rooms::Direct)  # Skip DMs - handled separately

    non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, activity_until)
    m.read_until(activity_until) if non_mentions.none?
  end
end

# Marks all direct message rooms as read up to the loaded timestamp.
def mark_direct_messages_as_read(loaded_at)
  dms_until = freshness_checked_time(loaded_at)

  memberships.unread.direct_rooms.each do |m|
    m.read_until(dms_until)
  end
end
```

### 2. Routes

**`config/routes.rb`**
```ruby
resource :inbox, only: %i[ show ] do
  member do
    get :activity
    get :direct_messages  # NEW
    get :threads
    # ...
    post :clear
  end
  scope path: "/paged", as: :paged do
    resources :activity, only: %i[ index ], controller: "inboxes/activity"
    resources :direct_messages, only: %i[ index ], controller: "inboxes/direct_messages"  # NEW
    # ...
  end
end
```

### 3. Controllers

**`app/controllers/inboxes_controller.rb`** - Added `direct_messages` action
```ruby
def direct_messages
  session[:inbox_last_loaded_dms_created_at] = Time.current.iso8601
  @memberships = Inbox::DirectMessagesQuery.new(Current.user).call
  @direct_room_members = Rooms::Direct.members_for_display_by_room(
    @memberships.map(&:room_id),
    excluding: Current.user
  )
end

def clear
  case params[:scope]
  when "activity"
    Current.user.mark_activity_as_read(session[:inbox_last_loaded_activity_created_at])
  when "direct_messages"
    Current.user.mark_direct_messages_as_read(session[:inbox_last_loaded_dms_created_at])
  else
    # ... existing logic
  end
end
```

**`app/controllers/inboxes/direct_messages_controller.rb`** - NEW FILE
```ruby
class Inboxes::DirectMessagesController < InboxesController
  layout false

  def index
    @memberships = Inbox::DirectMessagesQuery.new(Current.user).call
    @direct_room_members = Rooms::Direct.members_for_display_by_room(
      @memberships.map(&:room_id),
      excluding: Current.user
    )

    render "inboxes/direct_messages/index"
  end
end
```

### 4. Views

**`app/views/inboxes/direct_messages.html.erb`** - NEW FILE
```erb
<% @page_title = "DMs" %>
<%= render layout: "inboxes/nav", locals: { title: "DMs" } do %>
  <%= button_to clear_inbox_path(scope: "direct_messages"), class: "btn", title: "Mark all DMs as read" do %>
    <%= icon_tag "check" %>
  <% end %>
<% end %>

<% content_for :messages do %>
  <div id="inbox" class="dm-list">
    <%= render partial: "inboxes/direct_messages/conversation",
               collection: @memberships,
               as: :membership,
               locals: { direct_room_members: @direct_room_members } %>
  </div>
  <%= turbo_stream_from Current.user, :inbox_direct_messages %>
<% end %>

<%= render template: 'inboxes/show' %>
```

**`app/views/inboxes/direct_messages/_conversation.html.erb`** - NEW FILE
- Shows avatar (single or group), names, timestamp
- Includes message preview with sender name and truncated text
- Unread indicator badge

**`app/views/inboxes/direct_messages/index.html.erb`** - NEW FILE (for paged/turbo)

**`app/views/inboxes/show.html.erb`** - Updated empty state for DMs
```ruby
when "DMs"
  {
    icon: "messages",
    headline: "No conversations yet",
    description: "Start a conversation by clicking the + DM button in the sidebar."
  }
```

**`app/views/users/sidebars/show.html.erb`** - Added DMs button after Activity
```erb
<%= link_to inbox_path, class: "btn sidebar__tool", data: { unread_indicator_target: "activity" } do %>
  <%= icon_tag "mentions" %>
  <span class="for-screen-reader">Activity</span>
  <span class="sidebar__tool-label">Activity</span>
<% end %>

<%= link_to direct_messages_inbox_path, class: "btn sidebar__tool", data: { unread_indicator_target: "dms" } do %>
  <%= icon_tag "messages" %>
  <span class="for-screen-reader">DMs</span>
  <span class="sidebar__tool-label">DMs</span>
<% end %>
```

### 5. JavaScript

**`app/frontend/controllers/unread_indicator_controller.js`** - NEW FILE (unified controller)

Instead of separate controllers for Activity and DMs indicators, a single generic controller handles both via configuration:

```javascript
import { Controller } from "@hotwired/stimulus"

// Generic unread indicator controller that toggles classes on named targets
// based on whether elements matching their selectors exist in the sidebar.
//
// Usage:
//   data-controller="unread-indicator"
//   data-unread-indicator-indicators-value='[{"selector":".room.badge","class":"has-unread-activity","target":"activity"},{"selector":".direct.unread","class":"has-unread-dms","target":"dms"}]'
//   data-unread-indicator-target="activity" (on the activity link)
//   data-unread-indicator-target="dms" (on the dms link)
export default class extends Controller {
  static targets = ["activity", "dms"]
  static values = { indicators: Array }

  connect() {
    this.updateIndicators()
    this.observer = new MutationObserver(() => this.updateIndicators())
    const sidebarContainer = this.element.querySelector('.sidebar__container')
    if (sidebarContainer) {
      this.observer.observe(sidebarContainer, {
        attributes: true,
        attributeFilter: ['class'],
        subtree: true,
        childList: true
      })
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  update() {
    this.updateIndicators()
  }

  updateIndicators() {
    this.indicatorsValue.forEach(indicator => {
      const target = this[`${indicator.target}Target`]
      if (!target) return
      const hasUnread = this.element.querySelectorAll(indicator.selector).length > 0
      target.classList.toggle(indicator.class, hasUnread)
    })
  }
}
```

**`app/frontend/controllers/activity_indicator_controller.js`** - DELETED (replaced by unified controller)

### 6. CSS

**`app/assets/stylesheets/application/sidebar.css`** - Added styles for:
- `.has-unread-dms::after` indicator (same styling as `.has-unread-activity`)
- `.dm-list` container
- `.dm-conversation` card with hover/unread states
- `.dm-conversation__avatar`, `__content`, `__header`, `__names`, `__time`, `__preview`, `__sender`, `__badge`

### 7. Channels

**`app/channels/inbox_direct_messages_channel.rb`** - NEW FILE
```ruby
class InboxDirectMessagesChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_direct_messages
  end
end
```

### 8. Jobs

**`app/jobs/broadcast_inbox_direct_messages_job.rb`** - NEW FILE (for real-time updates)

### 9. Tests

**`test/controllers/inboxes_controller_test.rb`** - Updated with:
- Tests for `direct_messages` action
- Tests verifying DMs are excluded from activity
- Tests for `clear` with `scope: "direct_messages"`

**`test/models/inbox/direct_messages_query_test.rb`** - NEW FILE

## Key Implementation Decisions

| Decision | Rationale |
|----------|-----------|
| Unified `unread_indicator_controller.js` | More flexible and DRY than separate controllers. Supports any number of indicator types via configuration. |
| `Rooms::Direct.members_for_display_by_room` | Class method for batch loading members avoids N+1 queries and encapsulates domain logic in the model. |
| Message preview in conversation partial | Users requested preview text. Query updated to eager load `last_message` with creator to avoid N+1. |
| CSS in `sidebar.css` | DM inbox styles relate to sidebar/tool navigation. Keeps related styles together. |

## Verification Checklist

- [x] `bin/rails test` - all tests pass
- [x] Visit `/inbox/activity` - shows only @mentions (no DMs)
- [x] Visit `/inbox/direct_messages` - shows DM conversation list
- [x] Activity icon badge appears only for unread @mentions
- [x] DMs icon badge appears only for unread DMs
- [x] Mark as read on Activity clears mentions only
- [x] Mark as read on DMs clears all DM unreads
- [x] DMs still appear in top sidebar horizontal scroll
- [x] Clicking a DM in the inbox navigates to the room
- [x] Message preview shows in DM list

## Future Work (Deferred)

- Add reactions to Activity view (requires new functionality)

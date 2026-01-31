# Plan: Split Activity and DMs into Separate Inbox Views

## Summary

Separate the current Activity inbox into two distinct views:
1. **Activity** - @mentions and @everyone only (no DMs)
2. **DMs** - Full DM inbox showing conversation list chronologically

DMs will remain visible in the top sidebar row (horizontal scroll) AND be accessible via a new DMs inbox button.

## Files to Modify

### 1. Models

**`app/models/inbox/activity_query.rb`** - Exclude DMs
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
        .includes(room: { memberships: { user: { avatar_attachment: { blob: :variant_records } } } })
        .order("rooms.last_active_at DESC")
  end

  private
  attr_reader :user
end
```

**`app/models/user.rb`** - Update `mark_activity_as_read` to only handle mentions (remove DM logic we just added)
```ruby
def mark_activity_as_read(loaded_at)
  activity_until = freshness_checked_time(loaded_at)

  memberships.unread.with_has_unread_notifications.each do |m|
    next unless m.has_unread_notifications?
    next if m.room.is_a?(Rooms::Direct)  # Skip DMs - handled separately

    non_mentions = m.room.messages.without_user_mentions(self).between(m.unread_at, activity_until)
    m.read_until(activity_until) if non_mentions.none?
  end
end
```

Add new method:
```ruby
def mark_direct_messages_as_read
  memberships.unread.direct_rooms.each do |m|
    m.read_until(Time.current)
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

**`app/controllers/inboxes_controller.rb`** - Add `direct_messages` action
```ruby
def direct_messages
  @memberships = Inbox::DirectMessagesQuery.new(Current.user).call
  @direct_room_members = preload_direct_room_members(@memberships)
end

def clear
  case params[:scope]
  when "activity"
    Current.user.mark_activity_as_read(session[:inbox_last_loaded_activity_created_at])
  when "direct_messages"  # NEW
    Current.user.mark_direct_messages_as_read
  else
    # ... existing logic
  end
  # ...
end

private

def preload_direct_room_members(memberships)
  return {} if memberships.empty?

  room_ids = memberships.map(&:room_id)
  all_memberships = Membership.active
    .where(room_id: room_ids)
    .includes(user: { avatar_attachment: { blob: :variant_records } })
    .group_by(&:room_id)

  all_memberships.transform_values do |ms|
    ms.map(&:user).reject { |u| u.id == Current.user.id }
  end
end
```

**`app/controllers/inboxes/direct_messages_controller.rb`** - NEW FILE
```ruby
class Inboxes::DirectMessagesController < InboxesController
  layout false

  def index
    @memberships = Inbox::DirectMessagesQuery.new(Current.user).call
    @direct_room_members = preload_direct_room_members(@memberships)

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
```erb
<% members = direct_room_members[membership.room_id] || [] %>
<%= link_to room_path(membership.room),
            class: ["dm-conversation", "unread": membership.unread?],
            id: dom_id(membership.room, :dm_inbox) do %>
  <div class="dm-conversation__avatars">
    <% if members.many? %>
      <%= avatar_group_tag(members.first(3), size: 40) %>
    <% elsif members.one? %>
      <%= avatar_image_tag(members.first, size: 40) %>
    <% else %>
      <%= avatar_image_tag(Current.user, size: 40) %>
    <% end %>
  </div>

  <div class="dm-conversation__details">
    <div class="dm-conversation__names">
      <%= members.any? ? members.map(&:name).to_sentence : "Note to self" %>
    </div>
    <div class="dm-conversation__preview txt-muted">
      <% if (last_message = membership.room.messages.last) %>
        <%= truncate(last_message.plain_text_body, length: 50) %>
      <% end %>
    </div>
  </div>

  <div class="dm-conversation__meta">
    <span class="dm-conversation__time txt-small txt-muted">
      <%= time_ago_in_words(membership.room.last_active_at) %>
    </span>
    <% if membership.unread? %>
      <span class="dm-conversation__badge"></span>
    <% end %>
  </div>
<% end %>
```

**`app/views/inboxes/direct_messages/index.html.erb`** - NEW FILE (for paged/turbo)
```erb
<%= render partial: "inboxes/direct_messages/conversation",
           collection: @memberships,
           as: :membership,
           locals: { direct_room_members: @direct_room_members } %>
```

**`app/views/inboxes/show.html.erb`** - Update empty state
```ruby
when "DMs"
  {
    icon: "messages",
    headline: "No conversations yet",
    description: "Start a conversation by clicking the + DM button in the sidebar."
  }
```

**`app/views/users/sidebars/show.html.erb`** - Add DMs button after Activity
```erb
<%= link_to inbox_path, class: "btn sidebar__tool", data: { activity_indicator_target: "icon" } do %>
  <%= icon_tag "mentions" %>
  <span class="for-screen-reader">Activity</span>
  <span class="sidebar__tool-label">Activity</span>
<% end %>

<%= link_to direct_messages_inbox_path, class: "btn sidebar__tool", data: { dms_indicator_target: "icon" } do %>
  <%= icon_tag "messages" %>
  <span class="for-screen-reader">DMs</span>
  <span class="sidebar__tool-label">DMs</span>
<% end %>
```

Also wrap with separate indicator controller:
```erb
<div data-controller="activity-indicator dms-indicator" ...>
```

### 5. JavaScript

**`app/frontend/controllers/activity_indicator_controller.js`** - Only check mentions
```javascript
updateIndicator() {
  // Only check for rooms with mentions badge (not DMs)
  const hasUnreadMentions = this.element.querySelectorAll('.room.badge').length > 0

  if (hasUnreadMentions) {
    this.iconTarget.classList.add('has-unread-activity')
  } else {
    this.iconTarget.classList.remove('has-unread-activity')
  }
}
```

**`app/frontend/controllers/dms_indicator_controller.js`** - NEW FILE
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "icon" ]

  connect() {
    this.updateIndicator()
    this.observer = new MutationObserver(() => this.updateIndicator())

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
    this.updateIndicator()
  }

  updateIndicator() {
    const hasUnreadDirects = this.element.querySelectorAll('.direct.unread').length > 0

    if (hasUnreadDirects) {
      this.iconTarget.classList.add('has-unread-dms')
    } else {
      this.iconTarget.classList.remove('has-unread-dms')
    }
  }
}
```

### 6. CSS

**`app/assets/stylesheets/application/sidebar.css`** - Add DMs indicator style
```css
&.has-unread-dms::after {
  /* Same styling as has-unread-activity */
}
```

**`app/assets/stylesheets/application/inbox.css`** or similar - Add DM conversation list styles
```css
.dm-conversation {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--color-border);
}

.dm-conversation.unread {
  background: var(--color-surface-hover);
}

.dm-conversation__details {
  flex: 1;
  min-width: 0;
}

.dm-conversation__names {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dm-conversation__preview {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dm-conversation__badge {
  width: 8px;
  height: 8px;
  background: var(--color-negative);
  border-radius: 50%;
}
```

### 7. Channels (Optional)

**`app/channels/inbox_direct_messages_channel.rb`** - NEW FILE (if real-time updates needed)
```ruby
class InboxDirectMessagesChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_direct_messages
  end
end
```

### 8. Tests

**`test/controllers/inboxes_controller_test.rb`**
- Add tests for `direct_messages` action
- Update `activity` tests to verify DMs are excluded
- Add test for `clear` with `scope: "direct_messages"`

**`test/models/inbox/direct_messages_query_test.rb`** - NEW FILE

## Execution Order

1. Create `Inbox::DirectMessagesQuery`
2. Update `Inbox::ActivityQuery` to exclude DMs
3. Update `User#mark_activity_as_read` (remove DM handling)
4. Add `User#mark_direct_messages_as_read`
5. Add routes
6. Add controller action and new controller
7. Create views (main + partial + paged)
8. Update sidebar to add DMs button
9. Split indicator controllers
10. Add CSS styles
11. Update/add tests

## Verification

1. Run `bin/rails test` - all tests pass
2. Manual testing:
   - Visit `/inbox/activity` - should show only @mentions (no DMs)
   - Visit `/inbox/direct_messages` - should show DM conversation list
   - Activity icon badge appears only for unread @mentions
   - DMs icon badge appears only for unread DMs
   - Mark as read on Activity clears mentions only
   - Mark as read on DMs clears all DM unreads
   - DMs still appear in top sidebar horizontal scroll
   - Clicking a DM in the inbox navigates to the room

## Future Work (Deferred)

- Add reactions to Activity view (requires new functionality)

require "test_helper"

class Users::SidebarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show" do
    get user_sidebar_url

    users(:david).rooms.opens.each do |room|
      assert_match /#{room.name}/, @response.body
    end

    # Starred rooms render only under Favorites.
    assert_select "#starred_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:watercooler), "starred_rooms_list_node")}", count: 1
    assert_select "#shared_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:watercooler), "shared_rooms_list_node")}", count: 0

    assert_select "#starred_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:hq), "starred_rooms_list_node")}", count: 1
    assert_select "#shared_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:hq), "shared_rooms_list_node")}", count: 0

    # Unstarred rooms render only under All Rooms.
    assert_select "#shared_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:pets), "shared_rooms_list_node")}", count: 1
    assert_select "#starred_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:pets), "starred_rooms_list_node")}", count: 0
  end

  test "forum rows carry no row menu, while ordinary rooms do" do
    rooms(:help_desk).memberships.grant_to(users(:david))

    get user_sidebar_url

    forum_node = "#forum_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:help_desk), "forum_rooms_list_node")}"
    assert_select forum_node
    assert_select "#{forum_node} .room-row__menu-btn", count: 0

    room_node = "#shared_rooms ##{ActionView::RecordIdentifier.dom_id(rooms(:pets), "shared_rooms_list_node")}"
    assert_select "#{room_node} .room-row__menu-btn", count: 1
  end

  test "the sidebar direct-messages button opens the DM index, not an inline picker" do
    get user_sidebar_url

    assert_select "a[href=?][aria-label=?]", inbox_direct_messages_path, "Direct messages"
    assert_select "a[data-turbo-frame='direct_rooms_control']", count: 0
  end

  test "renders readable direct-message names — full name for one-on-one, comma-joined first names for groups" do
    one_on_one = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:rachel) ])
    group = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), users(:rachel), users(:jason) ])

    get user_sidebar_url

    one_on_one_author = css_select("##{ActionView::RecordIdentifier.dom_id(one_on_one, :list)} .direct__author").first
    assert one_on_one_author, "expected the one-on-one DM row to render"
    assert_includes one_on_one_author.text, "Rachel Green"

    group_author = css_select("##{ActionView::RecordIdentifier.dom_id(group, :list)} .direct__author").first
    assert group_author, "expected the group DM row to render"
    assert_includes group_author.text, "Rachel"
    assert_includes group_author.text, "Jason"
    assert_not_includes group_author.text, "Green"  # first names only
    assert_not_includes group_author.text, "+"      # not the old initials style
  end

  test "profile flyout renders administrator destinations and keeps the workspace settings gear" do
    accounts(:signal).settings.allow_users_to_create_invite_links = false
    accounts(:signal).save!

    get user_sidebar_url

    assert_select ".sidebar__profile-popover" do
      assert_select "a.sidebar__profile-summary[href=?]", user_path(users(:david))
      assert_select "a[href=?]", user_profile_path, text: "Your settings"
      assert_select "a[href=?] span", user_appearance_path, text: "Appearance"
      assert_select "a", text: "Invitations", count: 0
      assert_select "a[href=?] span", edit_account_path, text: "Community settings"
      assert_select "a[href=?] .sidebar__profile-menu-chip", edit_account_path, text: "STAFF"
      assert_select "form[action=?][data-controller~='sessions']", session_path do
        assert_select "input[type='hidden'][name='push_subscription_endpoint'][data-sessions-target='pushSubscriptionEndpoint']"
        assert_select "button[data-action~='sessions#logout:prevent']", text: "Log out"
      end
      assert_select ".sidebar__profile-presence", count: 0
    end

    assert_select ".sidebar__workspace a[href=?][title=?]", edit_account_path, "Community settings"
    assert_select ".sidebar__footer > .sidebar__profile", count: 1
    assert_select ".sidebar__footer > *", count: 1
  end

  test "profile flyout renders member destinations when personal invitations are allowed" do
    sign_in :kevin

    get user_sidebar_url

    assert_select ".sidebar__profile-popover" do
      assert_select "a.sidebar__profile-summary[href=?]", user_path(users(:kevin))
      assert_select "a[href=?]", user_profile_path, text: "Your settings"
      assert_select "a[href=?] span", user_appearance_path, text: "Appearance"
      assert_select "a[href=?]", user_invitations_path, text: "Invitations"
      assert_select "a", text: "Community settings", count: 0
      assert_select "form[action=?] button", session_path, text: "Log out"
    end

    assert_select ".sidebar__workspace a[title=?]", "Community settings", count: 0
  end

  test "profile flyout hides invitations when member invite links are disabled" do
    accounts(:signal).settings.allow_users_to_create_invite_links = false
    accounts(:signal).save!
    sign_in :kevin

    get user_sidebar_url

    assert_select ".sidebar__profile-popover" do
      assert_select "a", text: "Invitations", count: 0
      assert_select "a", text: "Community settings", count: 0
      assert_select "form[action=?] button", session_path, text: "Log out"
    end
  end

  test "unread directs" do
    rooms(:david_and_jason).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Direct rooms only appear once (in direct_rooms section)
    assert_select ".unread", count: users(:david).memberships.select { |m| m.room.direct? && m.unread? }.count
  end


  test "unread other" do
    rooms(:watercooler).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Non-direct rooms appear in one section only (starred or shared)
    unread_count = users(:david).memberships.reject { |m| m.room.direct? || !m.unread? }.count
    assert_select ".unread", count: unread_count
  end

  test "does not render a notification preferences link in the sidebar tools" do
    get user_sidebar_url

    assert_select ".sidebar__tools a[href=?]", edit_user_notification_settings_path, count: 0
  end

  test "activity link shows has-unread-activity when there are unseen notifications" do
    users(:david).update_column(:activity_seen_at, nil)
    rooms(:pets).messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "sidebar_activity_dot"
    )

    get user_sidebar_url
    assert_select "#sidebar_activity_indicator.has-unread-activity", count: 1
  end

  test "activity link omits has-unread-activity when watermark is current" do
    users(:david).touch_activity_seen_at(Time.current)

    get user_sidebar_url
    assert_select "#sidebar_activity_indicator", count: 1
    assert_select "#sidebar_activity_indicator.has-unread-activity", count: 0
  end

  test "activity link opts out of Turbo prefetch so hover doesn't clear the dot" do
    get user_sidebar_url
    assert_select "#sidebar_activity_indicator[data-turbo-prefetch=?]", "false"
  end

  test "direct room members are preloaded to avoid N+1 queries" do
    # Create messages in direct rooms so they appear in sidebar
    rooms(:david_and_jason).messages.create! client_message_id: 901, body: "Hello", creator: users(:jason)
    rooms(:david_and_kevin).messages.create! client_message_id: 902, body: "Hi", creator: users(:kevin)

    # Count queries during sidebar load
    query_count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      # Count User Load queries that fetch users for direct rooms
      query_count += 1 if payload[:sql] =~ /SELECT.*FROM "users".*"memberships"."room_id"/
    }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get user_sidebar_url
    end

    assert_response :success

    # Should have at most 1 batched query for all direct room users, not N queries
    # (one per room would be N+1)
    assert query_count <= 1, "Expected at most 1 batched user query for direct rooms, got #{query_count}"
  end
end

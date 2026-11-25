require "test_helper"

class Users::SidebarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show" do
    get user_sidebar_url

    users(:david).channels.opens.each do |channel|
      assert_match /#{channel.name}/, @response.body
    end

    # Starred channels render only under Favorites.
    assert_select "#starred_channels ##{ActionView::RecordIdentifier.dom_id(channels(:watercooler), "starred_channels_list_node")}", count: 1
    assert_select "#shared_channels ##{ActionView::RecordIdentifier.dom_id(channels(:watercooler), "shared_channels_list_node")}", count: 0

    assert_select "#starred_channels ##{ActionView::RecordIdentifier.dom_id(channels(:hq), "starred_channels_list_node")}", count: 1
    assert_select "#shared_channels ##{ActionView::RecordIdentifier.dom_id(channels(:hq), "shared_channels_list_node")}", count: 0

    # Unstarred channels render only under All Channels.
    assert_select "#shared_channels ##{ActionView::RecordIdentifier.dom_id(channels(:pets), "shared_channels_list_node")}", count: 1
    assert_select "#starred_channels ##{ActionView::RecordIdentifier.dom_id(channels(:pets), "starred_channels_list_node")}", count: 0
  end

  test "unread directs" do
    channels(:david_and_jason).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Direct channels only appear once (in direct_channels section)
    assert_select ".unread", count: users(:david).memberships.select { |m| m.channel.direct? && m.unread? }.count
  end


  test "unread other" do
    channels(:watercooler).messages.create! client_message_id: 999, body: "Hello", creator: users(:jason)

    get user_sidebar_url
    # Non-direct channels appear in one section only (starred or shared)
    unread_count = users(:david).memberships.reject { |m| m.channel.direct? || !m.unread? }.count
    assert_select ".unread", count: unread_count
  end

  test "does not render a notification preferences link in the sidebar tools" do
    get user_sidebar_url

    assert_select ".sidebar__tools a[href=?]", edit_user_notification_settings_path, count: 0
  end

  test "activity link shows has-unread-activity when there are unseen notifications" do
    users(:david).update_column(:activity_seen_at, nil)
    channels(:pets).messages.create!(
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

  test "direct channel members are preloaded to avoid N+1 queries" do
    # Create messages in direct channels so they appear in sidebar
    channels(:david_and_jason).messages.create! client_message_id: 901, body: "Hello", creator: users(:jason)
    channels(:david_and_kevin).messages.create! client_message_id: 902, body: "Hi", creator: users(:kevin)

    # Count queries during sidebar load
    query_count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      # Count User Load queries that fetch users for direct channels
      query_count += 1 if payload[:sql] =~ /SELECT.*FROM "users".*"memberships"."channel_id"/
    }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get user_sidebar_url
    end

    assert_response :success

    # Should have at most 1 batched query for all direct channel users, not N queries
    # (one per channel would be N+1)
    assert query_count <= 1, "Expected at most 1 batched user query for direct channels, got #{query_count}"
  end
end

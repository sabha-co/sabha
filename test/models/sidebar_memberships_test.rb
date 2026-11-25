require "test_helper"

class SidebarMembershipsTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @kevin = users(:kevin)
    @sidebar = SidebarMemberships.new(@david)
  end

  # --- direct ---

  test "direct returns direct channels even without messages" do
    # DMs should show as long as they're recently active (within 7 days)
    channel = channels(:david_and_jason)
    channel.update!(updated_at: 1.day.ago)

    direct = @sidebar.direct

    assert_includes direct.map(&:channel), channel
  end

  test "direct returns direct channels with messages that are recently active" do
    channel = channels(:david_and_jason)
    channel.update!(updated_at: 1.day.ago)
    channel.messages.create!(creator: @jason, body: "Hello")

    direct = @sidebar.direct

    assert_includes direct.map(&:channel), channel
  end

  test "direct excludes direct channels older than 7 days without unread messages" do
    channel = channels(:david_and_jason)
    channel.messages.create!(creator: @jason, body: "Hello")

    # Mark as read and set channel as old (after message creation to avoid callback updates)
    catch_up @david.memberships.find_by(channel: channel)
    channel.update_columns(updated_at: 10.days.ago)

    direct = @sidebar.direct

    assert_not_includes direct.map(&:channel), channel
  end

  test "direct includes old direct channels if they have unread messages" do
    channel = channels(:david_and_jason)
    message = channel.messages.create!(creator: @jason, body: "Hello")

    # Mark as unread and set channel as old
    rewind_unread_to @david.memberships.find_by(channel: channel), message
    channel.update_columns(updated_at: 10.days.ago)

    direct = @sidebar.direct

    assert_includes direct.map(&:channel), channel
  end

  test "direct excludes invisible memberships" do
    channel = channels(:david_and_jason)
    channel.update!(updated_at: 1.day.ago)
    channel.messages.create!(creator: @jason, body: "Hello")

    @david.memberships.find_by(channel: channel).update!(involvement: :invisible)

    direct = @sidebar.direct

    assert_not_includes direct.map(&:channel), channel
  end

  test "direct excludes inactive channels" do
    channel = channels(:david_and_jason)
    channel.update!(updated_at: 1.day.ago, active: false)
    channel.messages.create!(creator: @jason, body: "Hello")

    direct = @sidebar.direct

    assert_not_includes direct.map(&:channel), channel
  end

  # --- shared ---

  test "shared returns unstarred open and closed channel memberships" do
    shared = @sidebar.shared

    # watercooler and hq are starred in fixtures, so they appear in starred instead
    assert_not_includes shared.map(&:channel), channels(:watercooler)
    assert_not_includes shared.map(&:channel), channels(:hq)
    assert_includes shared.map(&:channel), channels(:pets)
    assert_includes shared.map(&:channel), channels(:designers)
  end

  test "shared excludes direct channels" do
    shared = @sidebar.shared

    assert_not_includes shared.map(&:channel), channels(:david_and_jason)
    assert_not_includes shared.map(&:channel), channels(:david_and_kevin)
  end

  test "shared excludes invisible memberships" do
    @david.memberships.find_by(channel: channels(:watercooler)).update!(involvement: :invisible)

    shared = @sidebar.shared

    assert_not_includes shared.map(&:channel), channels(:watercooler)
  end

  # --- direct_channel_members ---

  test "direct_channel_members returns users excluding current user" do
    channel = channels(:david_and_jason)
    channel.messages.create!(creator: @jason, body: "Hello")
    membership = @david.memberships.find_by(channel: channel)

    members = @sidebar.direct_channel_members([ membership ])

    assert_equal [ @jason ], members[channel.id]
  end

  test "direct_channel_members returns current user when they are the only member" do
    # Create a direct channel where david is the only member
    channel = Channels::Direct.create!(creator: @david)
    channel.memberships.create!(user: @david, involvement: :everything)
    channel.messages.create!(creator: @david, body: "Note to self")
    membership = @david.memberships.find_by(channel: channel)

    members = @sidebar.direct_channel_members([ membership ])

    assert_equal [ @david ], members[channel.id]
  end

  test "direct_channel_members handles multiple channels" do
    channel1 = channels(:david_and_jason)
    channel2 = channels(:david_and_kevin)
    channel1.messages.create!(creator: @jason, body: "Hello")
    channel2.messages.create!(creator: @kevin, body: "Hi")

    memberships = [
      @david.memberships.find_by(channel: channel1),
      @david.memberships.find_by(channel: channel2)
    ]

    members = @sidebar.direct_channel_members(memberships)

    assert_equal [ @jason ], members[channel1.id]
    assert_equal [ @kevin ], members[channel2.id]
  end
end

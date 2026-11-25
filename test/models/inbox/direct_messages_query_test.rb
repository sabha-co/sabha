require "test_helper"

class Inbox::DirectMessagesQueryTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @kevin = users(:kevin)
  end

  test "returns direct channel memberships for user" do
    dm_channel = channels(:david_and_jason)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_includes result.map(&:channel), dm_channel
  end

  test "excludes non-direct channels" do
    regular_channel = channels(:watercooler)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:channel), regular_channel
  end

  test "excludes invisible memberships" do
    dm_channel = channels(:david_and_jason)
    @david.memberships.find_by(channel: dm_channel).update!(involvement: :invisible)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:channel), dm_channel
  end

  test "excludes inactive channels" do
    dm_channel = channels(:david_and_jason)
    dm_channel.update!(active: false)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_not_includes result.map(&:channel), dm_channel
  end

  test "orders by channel last_active_at descending" do
    dm_channel1 = channels(:david_and_jason)
    dm_channel2 = channels(:david_and_kevin)

    dm_channel1.update!(last_active_at: 1.day.ago)
    dm_channel2.update!(last_active_at: 1.hour.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call

    assert_equal dm_channel2, result.first.channel
    assert_equal dm_channel1, result.second.channel
  end

  test "last_page returns limited results" do
    result = Inbox::DirectMessagesQuery.new(@david).call.last_page

    assert result.size <= Inbox::DirectMessagesQuery::ChannelPagination::PAGE_SIZE
  end

  test "page_after returns memberships with older last_active_at" do
    dm_channel1 = channels(:david_and_jason)
    dm_channel2 = channels(:david_and_kevin)

    dm_channel1.update!(last_active_at: 1.hour.ago)
    dm_channel2.update!(last_active_at: 2.hours.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call.page_after(dm_channel1)

    # Should include dm_channel2 which is older
    assert_includes result.map(&:channel), dm_channel2
    # Should not include dm_channel1 which is the anchor
    assert_not_includes result.map(&:channel), dm_channel1
  end

  test "page_before returns memberships with newer last_active_at" do
    dm_channel1 = channels(:david_and_jason)
    dm_channel2 = channels(:david_and_kevin)

    dm_channel1.update!(last_active_at: 1.hour.ago)
    dm_channel2.update!(last_active_at: 2.hours.ago)

    result = Inbox::DirectMessagesQuery.new(@david).call.page_before(dm_channel2)

    # Should include dm_channel1 which is newer
    assert_includes result.map(&:channel), dm_channel1
    # Should not include dm_channel2 which is the anchor
    assert_not_includes result.map(&:channel), dm_channel2
  end

  test "pagination handles channels with same last_active_at using id as tie-breaker" do
    dm_channel1 = channels(:david_and_jason)
    dm_channel2 = channels(:david_and_kevin)

    # Set both channels to the exact same timestamp
    same_time = 1.hour.ago
    dm_channel1.update_column(:last_active_at, same_time)
    dm_channel2.update_column(:last_active_at, same_time)

    # Determine which channel has higher id (appears first in DESC order)
    first_channel, second_channel = [ dm_channel1, dm_channel2 ].sort_by(&:id).reverse

    # page_after the first channel should include the second channel
    result = Inbox::DirectMessagesQuery.new(@david).call.page_after(first_channel)
    assert_includes result.map(&:channel), second_channel

    # page_before the second channel should include the first channel
    result = Inbox::DirectMessagesQuery.new(@david).call.page_before(second_channel)
    assert_includes result.map(&:channel), first_channel
  end
end

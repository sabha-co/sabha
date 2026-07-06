require "test_helper"

class Inbox::MessagesQueryTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @room = Rooms::Open.create_for({ name: "Inbox Room", creator: @david }, users: [ @david, @jason ])
  end

  # Regression: executing the query is the assertion — a missing memberships join
  # once raised SQLite3::SQLException: no such column: memberships.active here.
  test "the visible query runs and returns others' messages the user is involved in" do
    theirs = @room.messages.create!(body: "theirs", creator: @jason)
    mine   = @room.messages.create!(body: "mine", creator: @david)

    ids = Inbox::MessagesQuery.new(@david, involvement: :visible).call.map(&:id)

    assert_includes ids, theirs.id
    assert_not_includes ids, mine.id, "the inbox excludes the user's own messages"
  end

  test "the notifications_on query runs" do
    assert_nothing_raised { Inbox::MessagesQuery.new(@david, involvement: :notifications_on).call.to_a }
  end

  test "a room muted to invisible drops out of the visible inbox" do
    @david.memberships.find_by(room_id: @room.id).update!(involvement: :invisible)
    theirs = @room.messages.create!(body: "theirs", creator: @jason)

    ids = Inbox::MessagesQuery.new(@david, involvement: :visible).call.map(&:id)

    assert_not_includes ids, theirs.id
  end

  test "notifications_on surfaces only everything-involved rooms" do
    theirs = @room.messages.create!(body: "theirs", creator: @jason)

    ids = Inbox::MessagesQuery.new(@david, involvement: :notifications_on).call.map(&:id)
    assert_not_includes ids, theirs.id, "a mentions-level membership is not notifications_on"

    @david.memberships.find_by(room_id: @room.id).update!(involvement: :everything)
    ids = Inbox::MessagesQuery.new(@david, involvement: :notifications_on).call.map(&:id)
    assert_includes ids, theirs.id
  end

  test "rejects an invalid involvement" do
    assert_raises(ArgumentError) { Inbox::MessagesQuery.new(@david, involvement: :bogus) }
  end
end

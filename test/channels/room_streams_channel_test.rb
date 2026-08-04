require "test_helper"

# A room's message stream is authorized when the subscription is made, not just
# when the stream name is signed — a signed name has no expiry and no owner, so
# on its own it outlives the access that produced it.
class RoomStreamsChannelTest < ActionCable::Channel::TestCase
  tests RoomStreamsChannel

  setup do
    @room = rooms(:designers)
    @signed_stream_name = Turbo::StreamsChannel.signed_stream_name([ @room, :messages ])
  end

  test "a member may subscribe to a room's message stream" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: @signed_stream_name

    assert subscription.confirmed?
    assert_has_stream Turbo.signed_stream_verifier.verified(@signed_stream_name)
  end

  test "someone who was never a member may not subscribe" do
    stub_connection current_user: users(:rachel)

    subscribe signed_stream_name: @signed_stream_name

    assert subscription.rejected?
  end

  test "a revoked member may not resubscribe with a name harvested while a member" do
    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: @signed_stream_name
    assert subscription.confirmed?, "kevin must start out able to subscribe"

    @room.memberships.revoke_from [ users(:kevin) ]

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: @signed_stream_name

    assert subscription.rejected?
  end

  test "an unsigned stream name is rejected" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.send(:stream_name_from, [ @room, :messages ])

    assert subscription.rejected?
  end

  test "a tampered stream name is rejected" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: @signed_stream_name + "0"

    assert subscription.rejected?
  end

  # Sub-rooms derive access from their parent, so the check has to follow the
  # same rule the controllers do rather than demand a membership row.

  test "a forum member may subscribe to a post they've never followed" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to users(:kevin)
    post = Current.set(user: users(:jz)) { forum.post!(title: "Hello", body: "World") }

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ post, :messages ])

    assert subscription.confirmed?
  end

  test "an outsider may not subscribe to a post's message stream" do
    forum = rooms(:help_desk)
    post = Current.set(user: users(:jz)) { forum.post!(title: "Hello", body: "World") }

    stub_connection current_user: users(:rachel)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ post, :messages ])

    assert subscription.rejected?
  end

  test "a forum member may subscribe to the gallery's post stream, an outsider may not" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to users(:kevin)
    signed = Turbo::StreamsChannel.signed_stream_name([ forum, :posts ])

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: signed
    assert subscription.confirmed?

    stub_connection current_user: users(:rachel)
    subscribe signed_stream_name: signed
    assert subscription.rejected?
  end

  # The three-segment stream carries one person's own state — their bookmark
  # marks — so sharing the room isn't enough.

  test "a user-scoped room stream belongs to its owner alone" do
    signed = Turbo::StreamsChannel.signed_stream_name([ users(:kevin), @room, :messages ])

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: signed
    assert subscription.confirmed?

    stub_connection current_user: users(:jz)
    subscribe signed_stream_name: signed
    assert subscription.rejected?, "jz shares the room but not kevin's bookmark state"
  end
end

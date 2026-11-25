require "test_helper"

# A channel's message stream is authorized when the subscription is made, not just
# when the stream name is signed — a signed name has no expiry and no owner, so
# on its own it outlives the access that produced it.
class ChannelStreamsChannelTest < ActionCable::Channel::TestCase
  tests ChannelStreamsChannel

  setup do
    @channel = channels(:designers)
    @signed_stream_name = Turbo::StreamsChannel.signed_stream_name([ @channel, :messages ])
  end

  test "a member may subscribe to a channel's message stream" do
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

    @channel.memberships.revoke_from [ users(:kevin) ]

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: @signed_stream_name

    assert subscription.rejected?
  end

  test "an unsigned stream name is rejected" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.send(:stream_name_from, [ @channel, :messages ])

    assert subscription.rejected?
  end

  test "a tampered stream name is rejected" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: @signed_stream_name + "0"

    assert subscription.rejected?
  end

  # Sub-channels derive access from their parent, so the check has to follow the
  # same rule the controllers do rather than demand a membership row.

  test "a forum member may subscribe to a post they've never followed" do
    forum = channels(:help_desk)
    forum.memberships.grant_to users(:kevin)
    post = Current.set(user: users(:jz)) { forum.post!(title: "Hello", body: "World") }

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ post, :messages ])

    assert subscription.confirmed?
  end

  test "an outsider may not subscribe to a post's message stream" do
    forum = channels(:help_desk)
    post = Current.set(user: users(:jz)) { forum.post!(title: "Hello", body: "World") }

    stub_connection current_user: users(:rachel)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ post, :messages ])

    assert subscription.rejected?
  end

  test "a forum member may subscribe to the gallery's post stream, an outsider may not" do
    forum = channels(:help_desk)
    forum.memberships.grant_to users(:kevin)
    signed = Turbo::StreamsChannel.signed_stream_name([ forum, :posts ])

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: signed
    assert subscription.confirmed?

    stub_connection current_user: users(:rachel)
    subscribe signed_stream_name: signed
    assert subscription.rejected?
  end

  # What counts as a channel stream is read off the name, not matched against a list
  # of known suffixes, so a stream nobody has written yet is already covered.

  test "a channel stream with a suffix this channel has never seen is still guarded" do
    signed = Turbo::StreamsChannel.signed_stream_name([ @channel, :some_future_suffix ])

    stub_connection current_user: users(:rachel)
    subscribe signed_stream_name: signed
    assert subscription.rejected?, "an outsider must not reach a new channel stream either"

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: signed
    assert subscription.confirmed?
  end

  # The three-segment stream carries one person's own state — their bookmark
  # marks — so sharing the channel isn't enough.

  test "a user-scoped channel stream belongs to its owner alone" do
    signed = Turbo::StreamsChannel.signed_stream_name([ users(:kevin), @channel, :messages ])

    stub_connection current_user: users(:kevin)
    subscribe signed_stream_name: signed
    assert subscription.confirmed?

    stub_connection current_user: users(:jz)
    subscribe signed_stream_name: signed
    assert subscription.rejected?, "jz shares the channel but not kevin's bookmark state"
  end
end

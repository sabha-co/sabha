require "test_helper"

class Message::MentioneeTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @jz = users(:jz)
    @room = rooms(:pets)
  end

  # ===================
  # mentions_everyone flag tests
  # ===================

  test "creating a message with @everyone sets mentions_everyone flag" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_1"
    )

    assert message.mentions_everyone?
  end

  test "creating a message without mentions does not set mentions_everyone" do
    message = @room.messages.create!(
      body: "<div>Hello everyone!</div>",
      creator: @jason,
      client_message_id: "no_mention_1"
    )

    assert_not message.mentions_everyone?
  end

  test "editing @everyone message to remove @everyone resets flag" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_reset_1"
    )

    assert message.mentions_everyone?

    message.update!(body: "<div>Hey #{mention_attachment_for(:david)}</div>")

    assert_not message.reload.mentions_everyone?
  end

  test "editing a regular message to @everyone sets flag" do
    everyone_sgid = Everyone.new.attachable_sgid

    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "to_everyone_1"
    )

    assert_not message.mentions_everyone?

    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"
    message.update!(body: body_html)

    assert message.reload.mentions_everyone?
  end

  # ===================
  # mentionees method tests
  # ===================

  test "mentionees returns mentioned users filtered to room members" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "mentionees_1"
    )

    assert_equal [ @david ], message.mentionees.to_a
  end

  test "mentionees returns all room users for @everyone message" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_mentionees_1"
    )

    assert_equal @room.users.count, message.mentionees.count
    @room.users.each do |user|
      assert_includes message.mentionees, user
    end
  end

  test "mentionees excludes non-room-members for unsaved messages" do
    # kevin is not a member of pets room
    message = Message.new(
      room: @room,
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: @jason,
      client_message_id: "non_member_mention_1"
    )

    assert_empty message.mentionees
  end

  test "mentionees in a forum post reach a mentioned forum member who is not a follower" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: @david }, users: [ @david, @jz ])
    post = Current.set(user: @david) { forum.post!(title: "Q", body: "<div>b</div>") }
    assert_not post.followed_by?(@jz), "jz is a forum member but not a post follower"

    reply = post.messages.create!(
      body: "<div>Ping #{mention_attachment_for(:jz)}</div>",
      creator: @david,
      client_message_id: "post_mention_1"
    )

    assert_includes reply.mentionees, @jz
  end

  # ===================
  # mentionee_ids method tests
  # ===================

  test "mentionee_ids returns ids of mentioned room members" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "ids_1"
    )

    assert_equal [ @david.id ], message.mentionee_ids
  end

  test "mentionee_ids returns all room user ids for @everyone" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_ids_1"
    )

    assert_equal @room.user_ids.sort, message.mentionee_ids.sort
  end

  test "mentionee_ids excludes non-room-members for unsaved messages" do
    message = Message.new(
      room: @room,
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: @jason,
      client_message_id: "non_member_ids_1"
    )

    assert_empty message.mentionee_ids
  end

  # ===================
  # mentioning scope tests
  # ===================

  test "mentioning scope finds messages with mention notifications" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "scope_1"
    )

    # create_mention_notifications callback creates the notification
    assert_includes Message.mentioning(@david.id), message
  end

  test "mentioning scope finds @everyone messages" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "scope_everyone_1"
    )

    assert_includes Message.mentioning(@david.id), message
  end

  test "mentioning scope excludes messages not mentioning user" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "scope_exclude_1"
    )

    assert_not_includes Message.mentioning(@david.id), message
  end

  # ===================
  # cited_users tests (mentions via quoted messages)
  # ===================

  test "mentionees includes users from cited messages" do
    original_message = @room.messages.create!(
      body: "<div>Original message</div>",
      creator: @david,
      client_message_id: "cited_original_1"
    )

    citing_message = @room.messages.create!(
      body: "<div><cite><a href=\"/rooms/#{@room.id}/messages/@#{original_message.id}\">quoted</a></cite> responding</div>",
      creator: @jason,
      client_message_id: "citing_1"
    )

    assert_includes citing_message.mentionees, @david
  end

  # ===================
  # create defers the per-recipient activity indicator to a job (U9)
  # ===================

  test "creating a mention enqueues the broadcast job instead of rendering the indicator inline" do
    assert_turbo_stream_broadcasts [ @jason, :sidebar_activity_indicator ], count: 0 do
      assert_enqueued_with job: BroadcastMentionNotificationsJob do
        @room.messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: @david,
          client_message_id: "defer_indicator_1"
        )
      end
    end
  end

  test "the enqueued job renders the activity indicator for each recipient" do
    @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
      creator: @david,
      client_message_id: "defer_indicator_2"
    )

    assert_turbo_stream_broadcasts [ @jason, :sidebar_activity_indicator ], count: 1 do
      perform_enqueued_jobs only: BroadcastMentionNotificationsJob
    end
  end
end

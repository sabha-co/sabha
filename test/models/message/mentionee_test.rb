require "test_helper"

class Message::MentioneeTest < ActiveSupport::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @jz = users(:jz)
    @room = rooms(:pets)
  end

  # ===================
  # create_mentionees tests
  # ===================

  test "create_mentionees creates mention records for mentioned users" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "mention_create_1"
    )

    assert_equal 1, message.mentions.count
    assert message.mentions.exists?(user: @david)
  end

  test "create_mentionees handles multiple mentions" do
    # Add jz to pets room first
    @room.memberships.grant_to(@jz)

    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} and #{mention_attachment_for(:jz)}</div>",
      creator: @jason,
      client_message_id: "mention_multiple_1"
    )

    assert_equal 2, message.mentions.count
    assert message.mentions.exists?(user: @david)
    assert message.mentions.exists?(user: @jz)
  end

  test "create_mentionees deduplicates repeated mentions" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)} and again #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "mention_dupe_1"
    )

    assert_equal 1, message.mentions.count
    assert message.mentions.exists?(user: @david)
  end

  test "create_mentionees sets mentions_everyone for @everyone" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_1"
    )

    assert message.mentions_everyone?
    assert_equal 0, message.mentions.count, "Individual mention records should not be created for @everyone"
  end

  test "create_mentionees creates mention record even for non-room-members" do
    # This is the current behavior - mention records are created from attachables
    # The mentionees method filters by room membership, but create_mentionees does not
    # kevin is not a member of pets room
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:kevin)}</div>",
      creator: @jason,
      client_message_id: "non_member_mention_1"
    )

    # Mention record IS created (this is the current behavior)
    assert_equal 1, message.mentions.count

    # But mentionees (the filtered list) is empty since kevin is not a room member
    # Note: this behavior might be undesirable and could be fixed in refactoring
  end

  test "create_mentionees handles messages with no mentions" do
    message = @room.messages.create!(
      body: "<div>Hello everyone!</div>",
      creator: @jason,
      client_message_id: "no_mention_1"
    )

    assert_equal 0, message.mentions.count
    assert_not message.mentions_everyone?
  end

  test "create_mentionees runs on message update" do
    message = @room.messages.create!(
      body: "<div>Hello!</div>",
      creator: @jason,
      client_message_id: "update_mention_1"
    )

    assert_equal 0, message.mentions.count

    # Update to add a mention
    message.update!(body: "<div>Hey #{mention_attachment_for(:david)}</div>")

    assert_equal 1, message.mentions.count
    assert message.mentions.exists?(user: @david)
  end

  # ===================
  # mentionees method tests
  # ===================

  test "mentionees returns mentioned users for persisted message" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "mentionees_1"
    )

    assert_equal [ @david ], message.mentionees.to_a
  end

  test "mentionees returns all room users for @everyone message" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></div>"

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

  test "mentionees for unsaved message filters to room members only" do
    message = Message.new(
      room: @room,
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "unsaved_1"
    )

    assert_equal [ @david ], message.mentionees
  end

  # ===================
  # mentionee_ids method tests
  # ===================

  test "mentionee_ids returns ids of mentioned users" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "ids_1"
    )

    assert_equal [ @david.id ], message.mentionee_ids
  end

  test "mentionee_ids returns all room user ids for @everyone" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "everyone_ids_1"
    )

    assert_equal @room.user_ids.sort, message.mentionee_ids.sort
  end

  # ===================
  # mentioning scope tests
  # ===================

  test "mentioning scope finds messages mentioning user" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "scope_1"
    )

    assert_includes Message.mentioning(@david.id), message
  end

  test "mentioning scope finds @everyone messages" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></div>"

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
  # without_user_mentions scope tests
  # ===================

  test "without_user_mentions excludes messages mentioning user" do
    message = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "without_1"
    )

    assert_not_includes Message.without_user_mentions(@david), message
  end

  test "without_user_mentions excludes @everyone messages" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.campfire.mention\"></action-text-attachment></div>"

    message = Message.create!(
      room: @room,
      body: body_html,
      creator: @jason,
      client_message_id: "without_everyone_1"
    )

    assert_not_includes Message.without_user_mentions(@david), message
  end

  # Note: The current without_user_mentions scope behavior with messages that have
  # no mentions is complex due to left_outer_joins with null filtering.
  # Messages with no mentions have mentions.user_id as NULL, which doesn't match
  # where.not(mentions: { user_id: user.id }) in a standard way.

  # ===================
  # cited_users tests (mentions via quoted messages)
  # ===================

  test "create_mentionees includes users from cited messages" do
    # First create a message by david
    original_message = @room.messages.create!(
      body: "<div>Original message</div>",
      creator: @david,
      client_message_id: "cited_original_1"
    )

    # Create a message that cites the original
    citing_message = @room.messages.create!(
      body: "<div><cite><a href=\"/rooms/#{@room.id}/messages/@#{original_message.id}\">quoted</a></cite> responding</div>",
      creator: @jason,
      client_message_id: "citing_1"
    )

    # david should be mentioned via the citation
    assert citing_message.mentions.exists?(user: @david)
  end
end

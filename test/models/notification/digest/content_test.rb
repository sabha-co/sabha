require "test_helper"

class Notification::Digest::ContentTest < ActiveSupport::TestCase
  setup do
    @user = users(:jason)
    @actor = users(:david)
    @room = rooms(:pets)
  end

  test "preloads associations used by digest mail rendering" do
    everyone_sgid = Everyone.new.attachable_sgid
    everyone_message = @room.messages.create!(
      body: %(<div>Heads up <action-text-attachment sgid="#{everyone_sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment></div>),
      creator: @actor,
      client_message_id: "digest_content_everyone_#{SecureRandom.hex(4)}"
    )

    2.times do |i|
      @room.messages.create!(
        body: "<div>Digest preload #{i}</div>",
        creator: @actor,
        client_message_id: "digest_content_preload_#{i}_#{SecureRandom.hex(4)}"
      )
    end

    content = Notification::Digest::Content.new(@user)

    assert_includes content.everyone_mentions.map(&:id), everyone_message.id
    (content.everyone_mentions + content.excerpts).each do |message|
      assert message.association(:creator).loaded?, "creator should be preloaded for sender names"
      assert message.association(:room).loaded?, "room should be preloaded for room names"
      assert message.association(:rich_text_body).loaded?, "body should be preloaded for previews"
    end
  end
end

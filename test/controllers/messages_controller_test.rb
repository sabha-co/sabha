require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "once.sabha.test"

    sign_in :david
    @channel = channels(:watercooler)
    @messages = @channel.messages.ordered.to_a
  end

  test "index returns the last page by default" do
    get channel_messages_url(@channel)

    assert_response :success
    ensure_messages_present @messages.last
  end

  test "index returns a page before the specified message" do
    get channel_messages_url(@channel, before: @messages.third)

    assert_response :success
    ensure_messages_present @messages.first, @messages.second
    ensure_messages_not_present @messages.third, @messages.fourth, @messages.fifth
  end

  test "index returns a page after the specified message" do
    get channel_messages_url(@channel, after: @messages.third)

    assert_response :success
    ensure_messages_present @messages.fourth, @messages.fifth
    ensure_messages_not_present @messages.first, @messages.second, @messages.third
  end

  test "index returns no_content when there are no messages" do
    @channel.messages.update_all(active: false)

    get channel_messages_url(@channel)

    assert_response :no_content
  end

  test "get renders a single message belonging to the user" do
    message = @channel.messages.where(creator: users(:david)).first

    get channel_message_url(@channel, message)

    assert_response :success
    assert_select "##{dom_id(message)}"
  end

  test "creating a message broadcasts the message to the channel" do
    post channel_messages_url(@channel, format: :turbo_stream), params: { message: { body: "New one", client_message_id: 999 } }

    assert_rendered_turbo_stream_broadcast @channel, :messages, action: "append", target: [ @channel, :messages ] do
      assert_select ".message__body", text: /New one/
      assert_copy_link_button channel_at_message_url(@channel, Message.last, host: "once.sabha.test")
    end
  end

  test "creating a message publishes one shared channel nudge instead of per-user unread broadcasts" do
    # One account-wide publish on the signed channel-list stream regardless of
    # member count; each client derives its own unread state from it. No
    # per-user push (ReadChannelsChannel is the surviving per-user read-state
    # stream) and no global "unread_channels" broadcast (the original
    # thundering-herd fix).
    other_member = @channel.memberships.visible.where.not(user: users(:david)).first
    catch_up other_member
    other_member.update!(connected_at: nil)

    nudges = capture_broadcasts(Account.sole.channel_list_stream_name) do
      assert_no_broadcasts ReadChannelsChannel.broadcasting_for(other_member.user) do
        assert_no_broadcasts "unread_channels" do
          post channel_messages_url(@channel, format: :turbo_stream), params: { message: { body: "New one", client_message_id: SecureRandom.uuid } }
        end
      end
    end

    assert_equal 1, nudges.size
    assert_equal @channel.id, nudges.first["channelId"]
    assert_equal users(:david).id, nudges.first["creatorId"], "the nudge carries the sender so their own clients skip the dot"
  end

  test "mentioning a user in a channel they're not viewing refreshes their sidebar sort metadata" do
    # The shared nudge carries the sidebar sort keys (channelUpdatedAt, channelSize),
    # so a disconnected mentionee's sidebar re-floats the channel without a
    # per-user push; their client derives the unread dot from the nudge.
    jason_membership = @channel.memberships.find_by(user: users(:jason))
    catch_up jason_membership
    jason_membership.update!(connected_at: nil)

    nudges = capture_broadcasts(Account.sole.channel_list_stream_name) do
      post channel_messages_url(@channel, format: :turbo_stream),
        params: { message: { body: "<div>Hey #{mention_attachment_for(:jason)}</div>", client_message_id: SecureRandom.uuid } }
    end

    nudge = nudges.find { |n| n["channelId"] == @channel.id }
    assert nudge, "expected a shared channel-list nudge carrying the channel's sort metadata"
    assert_equal @channel.reload.messages_count, nudge["channelSize"]
    assert_equal @channel.last_active_at.iso8601, nudge["channelUpdatedAt"]
  end

  test "creating a mention defers the per-recipient broadcasts to jobs instead of rendering synchronously" do
    jason = users(:jason)
    badge_stream = UnreadNotificationsChannel.broadcasting_for(jason)

    # Neither the sidebar activity indicator nor the live badge push runs on the
    # request path; both ride background jobs so create latency stays flat.
    assert_turbo_stream_broadcasts [ jason, :sidebar_activity_indicator ], count: 0 do
      assert_no_broadcasts badge_stream do
        post channel_messages_url(@channel, format: :turbo_stream),
          params: { message: { body: "<div>Hey #{mention_attachment_for(:jason)}</div>", client_message_id: SecureRandom.uuid } }
      end
    end

    assert_enqueued_jobs 1, only: BroadcastMentionNotificationsJob
    assert_enqueued_jobs 1, only: BroadcastUnreadNotificationsJob
  end

  test "update updates a message belonging to the user" do
    message = @channel.messages.where(creator: users(:david)).first

    # One broadcast to the channel's :messages stream, one to the global :inbox stream.
    assert_turbo_stream_broadcasts [ @channel, :messages ], count: 1 do
      assert_turbo_stream_broadcasts [ Account.sole, :inbox ], count: 1 do
        put channel_message_url(@channel, message), params: { message: { body: "Updated body" } }
      end
    end

    assert_redirected_to channel_message_url(@channel, message)
    assert_equal "Updated body", message.reload.plain_text_body
  end

  test "destroy soft-deletes a message belonging to the user" do
    message = @channel.messages.where(creator: users(:david)).first

    # Soft deletion - count stays same but active count decreases.
    # One remove broadcast to the channel's :messages stream, one to the global :inbox stream.
    assert_difference -> { Message.active.count }, -1 do
      assert_turbo_stream_broadcasts [ @channel, :messages ], count: 1 do
        assert_turbo_stream_broadcasts [ Account.sole, :inbox ], count: 1 do
          delete channel_message_url(@channel, message, format: :turbo_stream)
          assert_response :success
        end
      end
    end
    assert_not message.reload.active?
  end

  test "ensure non-admin can't update a message belonging to another user" do
    sign_in :jz
    assert_not users(:jz).administrator?

    channel = channels(:designers)
    message = channel.messages.where(creator: users(:jason)).first

    put channel_message_url(channel, message), params: { message: { body: "Updated body" } }
    assert_response :forbidden
  end

  test "ensure non-admin can't destroy a message belonging to another user" do
    sign_in :jz
    assert_not users(:jz).administrator?

    channel = channels(:designers)
    message = channel.messages.where(creator: users(:jason)).first

    delete channel_message_url(channel, message, format: :turbo_stream)
    assert_response :forbidden
  end

  test "creating a message with a direct-uploaded attachment via signed_id" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("hello world"),
      filename: "test.txt",
      content_type: "text/plain"
    )

    assert_difference -> { Message.count }, 1 do
      post channel_messages_url(@channel, format: :turbo_stream),
        params: { message: { attachment: blob.signed_id, client_message_id: "test-123" } }
    end

    assert Message.last.attachment.attached?
    assert_equal "test.txt", Message.last.attachment.filename.to_s
  end

  test "mentioning a bot triggers webhook for that bot" do
    WebMock.stub_request(:post, webhooks(:bender).url).to_return(status: 200)

    assert_enqueued_jobs 1, only: Bot::WebhookJob do
      post channel_messages_url(@channel, format: :turbo_stream), params: { message: {
        body: "<div>Hey #{mention_attachment_for(:bender)}</div>", client_message_id: 999 } }
    end
  end

  test "edit renders a Trix-era link preview's details into the editor" do
    message = create_message_with_body \
      %(<div>https://example.com/ <action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" url="https://example.com/image.png" href="https://example.com/" filename="Example title" caption="Example description"></action-text-attachment></div>)

    content = edited_attachment_content(message)

    assert_equal "Example title", content.at_css(".og-embed__title a").text.strip
    assert_equal "https://example.com/", content.at_css(".og-embed__title a")["href"]
    assert_equal "Example description", content.at_css(".og-embed__description").text.strip
    assert_equal "https://example.com/image.png", content.at_css(".og-embed__image img")["src"]
  end

  test "edit rebuilds a hand-written link preview from its validated details" do
    markup = <<~HTML.squish
      <actiontext-opengraph-embed data-controller="pwn" data-action="click->pwn#run">
        <div class="og-embed"><div class="og-embed__title"><a href="/channels/1">Free cookies</a></div>
        <div class="og-embed__image"><img src="/channels/1/avatar" data-action="load->pwn#run"></div></div>
      </actiontext-opengraph-embed>
    HTML
    message = create_message_with_body \
      %(<p><action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" url="https://example.com/image.png" content="#{ERB::Util.html_escape(markup)}"></action-text-attachment></p>)

    content = edited_attachment_content(message)

    assert_equal "Free cookies", content.at_css(".og-embed__title").text.strip
    assert_nil content.at_css("a")
    assert_nil content.at_css("img")
    assert_no_match %r{channels/1|data-action|data-controller}, content.to_html
  end

  test "edit gives a mention saved under Trix the mention content type" do
    message = create_message_with_body \
      %(<div>Hey <action-text-attachment sgid="#{users(:jason).attachable_sgid}" content-type="application/octet-stream"></action-text-attachment></div>)

    get edit_channel_message_url(@channel, message)

    node = edited_attachment_node
    assert_equal User::Mentionable::CONTENT_TYPE, node["content-type"]
    assert_match "Jason", node["content"]
  end

  private
    def create_message_with_body(body)
      @channel.messages.create! body: body, client_message_id: SecureRandom.uuid, creator: users(:david)
    end

    def edited_attachment_content(message)
      get edit_channel_message_url(@channel, message)
      assert_response :success

      Nokogiri::HTML.fragment(edited_attachment_node["content"])
    end

    def edited_attachment_node
      editor = Nokogiri::HTML(response.body).at_css("lexxy-editor")
      Nokogiri::HTML.fragment(editor["value"]).at_css("action-text-attachment")
    end

    def ensure_messages_present(*messages, count: 1)
      messages.each do |message|
        assert_select "#" + dom_id(message), count:
      end
    end

    def ensure_messages_not_present(*messages)
      ensure_messages_present *messages, count: 0
    end

    def assert_copy_link_button(url)
      assert_select ".btn[data-copy-to-clipboard-content-value='#{url}']", text: /Copy link/
    end
end

require "test_helper"

class ChannelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index redirects to the user's last channel" do
    get channels_url
    assert_redirected_to channel_url(users(:david).channels.last)
  end

  test "show" do
    get channel_url(users(:david).channels.last)
    assert_response :success
  end

  test "show renders the direct-message nav header" do
    channel = channels(:david_and_kevin)

    get channel_url(channel)

    assert_response :success
    # The recipient titles the conversation, and the header links to the channel's
    # settings — the same header the provisional compose surface renders (channel: nil).
    assert_select "a.channel--current[href=?]", edit_channels_direct_path(channel) do
      assert_select "h1.channel__contents", text: /#{users(:kevin).name}/
    end
  end

  test "composer carries the @everyone confirm threshold, member count, and cap flag" do
    channel = channels(:pets)

    get channel_url(channel)

    assert_response :success
    assert_select "form#composer[data-composer-everyone-confirm-threshold-value=?]",
                  Rails.configuration.x.everyone_mention.confirm_threshold.to_s
    assert_select "form#composer[data-composer-everyone-member-count-value=?]", channel.active_member_count.to_s
    assert_select "form#composer[data-composer-everyone-capped-value='false']"
    assert_select ".composer__everyone-confirm[hidden]"
  end

  test "composer flags the @everyone cap when the channel is over the ceiling" do
    channel = channels(:pets)
    original = Rails.configuration.x.everyone_mention.ceiling
    Rails.configuration.x.everyone_mention.ceiling = 1

    get channel_url(channel)

    assert_select "form#composer[data-composer-everyone-capped-value='true']"
  ensure
    Rails.configuration.x.everyone_mention.ceiling = original
  end

  test "show renders the new-messages separator inside the first unread message" do
    channel = channels(:pets)
    channel.messages.create!(creator: users(:jason), body: "Seen already", client_message_id: "separator_seen")
    first_unread = channel.messages.create!(creator: users(:jason), body: "New to you", client_message_id: "separator_unread")
    rewind_unread_to channel.memberships.find_by!(user: users(:david)), first_unread

    get channel_url(channel)

    assert_response :success
    assert_select "[data-message-id='#{first_unread.id}'] #unread_separator", count: 1
  end

  test "show renders no new-messages separator when the membership is read" do
    channel = channels(:pets)
    channel.messages.create!(creator: users(:jason), body: "Nothing new", client_message_id: "separator_none")
    catch_up channel.memberships.find_by!(user: users(:david))

    get channel_url(channel)

    assert_response :success
    assert_select "#unread_separator", count: 0
  end

  test "shows records the last channel visited in a cookie" do
    get channel_url(users(:david).channels.last)
    assert_equal users(:david).channels.last.id.to_s, response.cookies["last_channel"]
  end

  test "show drops a hand-written link preview's off-scheme link and image" do
    channel = channels(:watercooler)
    post channel_messages_url(channel, format: :turbo_stream), params: { message: {
      body: link_preview_body(href: "javascript:alert(1)", url: "data:image/svg+xml;base64,PHN2Zy8+"),
      client_message_id: "hand-written-preview" } }
    assert_response :success

    get channel_url(channel)

    assert_response :success
    # The dangerous values never reach a rendered sink: no link points at them
    # and no image is fetched from them. (An inert url= attribute may linger on
    # the <action-text-attachment> wrapper in stored markup, which a browser
    # neither fetches nor executes.)
    assert_no_match %r{href="javascript:}, response.body
    assert_no_match %r{<img src="data:}, response.body
  end

  test "show drops a hand-written link preview aimed at this Sabha" do
    channel = channels(:watercooler)
    own_url = channel_url(channel, host: "www.example.com")
    post channel_messages_url(channel, format: :turbo_stream), params: { message: {
      body: link_preview_body(href: own_url, url: own_url),
      client_message_id: "same-host-preview" } }
    assert_response :success

    get channel_url(channel)

    assert_response :success
    assert_no_match %r{<img src="#{Regexp.escape(own_url)}"}, response.body
    assert_no_match %r{<a rel="noreferrer" target="_blank" href="#{Regexp.escape(own_url)}"}, response.body
  end

  test "show renders an unfurled link preview" do
    channel = channels(:watercooler)
    post channel_messages_url(channel, format: :turbo_stream), params: { message: {
      body: link_preview_body(href: "https://example.com/page", url: "https://example.com/image.png"),
      client_message_id: "unfurled-preview" } }
    assert_response :success

    get channel_url(channel)

    assert_response :success
    assert_match %r{<img src="https://example\.com/image\.png"}, response.body
    assert_match %r{href="https://example\.com/page"}, response.body
  end

  test "destroy" do
    # 2 broadcasts: one for :starred_channels and one for :shared_channels
    assert_turbo_stream_broadcasts [ accounts(:signal), :channels ], count: 2 do
      assert_difference -> { Channel.active.count }, -1 do
        delete channel_url(channels(:designers))
      end
    end
  end

  test "destroy redirects with alert for original channel" do
    assert_no_difference -> { Channel.active.count } do
      delete channel_url(channels(:hq))
    end

    assert_equal "The original channel can't be deleted", flash[:alert]
  end

  test "show redirects thread channels to parent channel" do
    parent_message = channels(:pets).messages.create!(
      body: "Thread parent",
      creator: users(:jason),
      client_message_id: "redirect_thread_1"
    )
    thread = Channels::Thread.create_for(
      { parent_message_id: parent_message.id, creator: users(:jason) },
      users: [ users(:david), users(:jason) ]
    )

    get channel_url(thread)
    assert_redirected_to channel_at_message_url(parent_message.channel, parent_message)
  end

  test "index skips thread channels" do
    parent_message = channels(:pets).messages.create!(
      body: "Thread parent for index",
      creator: users(:jason),
      client_message_id: "index_thread_1"
    )
    Channels::Thread.create_for(
      { parent_message_id: parent_message.id, creator: users(:jason) },
      users: [ users(:david) ]
    )

    get channels_url
    # Should redirect to a non-thread channel, not the thread
    assert_redirected_to channel_url(users(:david).channels.without_threads.last)
  end

  test "DM back button links to referrer when coming from activity" do
    dm_channel = channels(:david_and_jason)

    get channel_url(dm_channel), headers: { "HTTP_REFERER" => inbox_activity_index_url }
    assert_response :success
    assert_select "a[href='#{inbox_activity_index_path}']"
  end

  test "DM back button defaults to DM inbox without referrer" do
    dm_channel = channels(:david_and_jason)

    get channel_url(dm_channel)
    assert_response :success
    assert_select "a[href='#{inbox_direct_messages_path}']"
  end

  test "DM back button prefers from param over referrer" do
    dm_channel = channels(:david_and_jason)

    get channel_url(dm_channel, from: inbox_threads_path), headers: { "HTTP_REFERER" => inbox_activity_index_url }
    assert_response :success
    assert_select "a[href='#{inbox_threads_path}']"
  end

  test "back button ignores non-inbox referrers for DMs" do
    dm_channel = channels(:david_and_jason)

    get channel_url(dm_channel), headers: { "HTTP_REFERER" => channel_url(channels(:hq)) }
    assert_response :success
    assert_select "a[href='#{inbox_direct_messages_path}']"
  end

  test "back button preserves search query string from referrer" do
    dm_channel = channels(:david_and_jason)

    get channel_url(dm_channel), headers: { "HTTP_REFERER" => "http://www.example.com/searches?q=hello" }
    assert_response :success
    assert_select "a[href='/searches?q=hello']"
  end

  test "destroy only allowed for creators or those who can administer" do
    sign_in :jz

    assert_no_difference -> { Channel.active.count } do
      delete channel_url(channels(:designers))
      assert_response :forbidden
    end

    channels(:designers).update! creator: users(:jz)

    assert_difference -> { Channel.active.count }, -1 do
      delete channel_url(channels(:designers))
    end
  end

  private
    def link_preview_body(href:, url:)
      %(<div><action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" ) +
        %(href="#{href}" url="#{url}" filename="Free cookies" caption="Cookies here"></action-text-attachment></div>)
    end
end

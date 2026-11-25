require "test_helper"

class Channels::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "add a member to a closed channel" do
    channel = channels(:designers)

    assert_difference -> { channel.reload.memberships.visible.count } do
      post channel_members_url(channel), params: { user_id: users(:bender).id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "add a member posts a joined event" do
    channel = channels(:designers)

    assert_difference -> { Message.unscoped.where(channel: channel, event: "member_joined").count } do
      post channel_members_url(channel), params: { user_id: users(:bender).id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "remove a member from a closed channel" do
    channel = channels(:designers)

    assert_difference -> { channel.reload.memberships.visible.count }, -1 do
      delete channel_member_url(channel, users(:jason)),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "remove a member posts a left event" do
    channel = channels(:designers)

    assert_difference -> { Message.unscoped.where(channel: channel, event: "member_left").count } do
      delete channel_member_url(channel, users(:jason)),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "cannot remove last visible member from a closed channel" do
    channel = channels(:designers)
    visible = channel.memberships.visible.to_a
    visible[1..].each { |m| m.update!(involvement: :invisible) }

    assert_no_difference -> { channel.reload.memberships.visible.count } do
      delete channel_member_url(channel, visible.first.user),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :unprocessable_entity
  end

  test "non-admin cannot add members" do
    sign_in :jz

    post channel_members_url(channels(:designers)), params: { user_id: users(:bender).id },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :forbidden
  end

  test "non-admin cannot remove members" do
    sign_in :jz

    delete channel_member_url(channels(:designers), users(:jason)),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :forbidden
  end
end

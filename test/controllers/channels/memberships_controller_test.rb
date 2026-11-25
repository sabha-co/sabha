require "test_helper"

class Channels::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "joining an open channel creates membership and redirects to channel with notice" do
    channel = channels(:pets)
    channel.memberships.where(user: users(:kevin)).update_all(active: false)

    assert_difference -> { Membership.where(channel: channel, user: users(:kevin), active: true).count } do
      post channel_membership_url(channel)
    end

    assert_redirected_to channel_url(channel)
    assert_equal "Joined #{channel.name}", flash[:notice]
  end

  test "joining a closed channel is not allowed" do
    Membership.where(channel: channels(:designers), user: users(:kevin)).update_all(active: false)

    assert_raises ActiveRecord::RecordNotFound do
      post channel_membership_url(channels(:designers))
    end
  end

  test "leaving a channel sets involvement to invisible" do
    sign_in :david
    channel = channels(:watercooler)

    delete channel_membership_url(channel)

    assert_redirected_to root_url
    assert_equal "You left #{channel.name}", flash[:notice]
    assert memberships(:david_watercooler).reload.involved_in_invisible?
  end

  test "cannot leave a direct channel" do
    sign_in :david

    delete channel_membership_url(channels(:david_and_jason))

    assert_redirected_to channel_url(channels(:david_and_jason))
    assert_equal "Cannot leave direct messages", flash[:alert]
  end
end

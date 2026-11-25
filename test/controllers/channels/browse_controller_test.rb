require "test_helper"

class Channels::BrowseControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "an auto-joined forum is not listed in Browse" do
    Channels::Forum.create_for({ name: "Everyone Forum", creator: users(:david) }, users: users(:david))

    get channels_browse_url

    assert_response :success
    assert_select "strong", text: "Everyone Forum", count: 0
  end

  test "a forum a member was removed from reappears in Browse so they can rejoin" do
    forum = Channels::Forum.create_for({ name: "Discoverable Forum", creator: users(:david) }, users: users(:david))
    forum.remove_member!(users(:kevin), actor: users(:david))

    get channels_browse_url

    assert_response :success
    assert_select "#browsable_channels strong", text: "Discoverable Forum"
  end

  test "rejoining a browsable forum grants membership and lands on the gallery" do
    forum = Channels::Forum.create_for({ name: "Joinable", creator: users(:david) }, users: users(:david))
    forum.remove_member!(users(:kevin), actor: users(:david))

    assert_difference -> { forum.memberships.count }, 1 do
      post channel_membership_url(forum)
    end

    assert_includes forum.reload.users, users(:kevin)
    assert_redirected_to channel_url(forum)
  end
end

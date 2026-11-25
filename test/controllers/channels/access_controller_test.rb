require "test_helper"

class Channels::AccessControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "opening a closed channel converts it in place" do
    patch channel_access_url(channels(:designers)), params: { open: "1" }

    assert_redirected_to edit_channels_open_url(channels(:designers))
    assert_equal "Channels::Open", Channel.find(channels(:designers).id).type
  end

  test "closing an open channel converts it in place" do
    patch channel_access_url(channels(:pets)), params: { open: "0" }

    assert_redirected_to edit_channels_closed_url(channels(:pets))
    assert_equal "Channels::Closed", Channel.find(channels(:pets).id).type
  end

  test "a direct channel has no access toggle to flip" do
    patch channel_access_url(channels(:david_and_kevin)), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Channels::Direct", Channel.find(channels(:david_and_kevin).id).type
  end

  test "a forum has no access toggle to flip" do
    channels(:help_desk).memberships.grant_to(users(:david))

    patch channel_access_url(channels(:help_desk)), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Channels::Forum", Channel.find(channels(:help_desk).id).type
  end

  test "a chat thread has no access toggle to flip" do
    sign_in :kevin
    message = channels(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Channels::Thread.find_or_create_for(message, creator: users(:kevin))

    patch channel_access_url(thread), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Channels::Thread", Channel.find(thread.id).type
    assert_not Channel.browsable_by(users(:rachel)).exists?(id: thread.id)
  end

  test "a non-member can't reach the toggle" do
    sign_in :rachel

    assert_raises ActiveRecord::RecordNotFound do
      patch channel_access_url(channels(:designers)), params: { open: "1" }
    end

    assert_equal "Channels::Closed", Channel.find(channels(:designers).id).type
  end
end

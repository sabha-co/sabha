require "test_helper"

class Rooms::AccessControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "opening a closed room converts it in place" do
    patch room_access_url(rooms(:designers)), params: { open: "1" }

    assert_redirected_to edit_rooms_open_url(rooms(:designers))
    assert_equal "Rooms::Open", Room.find(rooms(:designers).id).type
  end

  test "closing an open room converts it in place" do
    patch room_access_url(rooms(:pets)), params: { open: "0" }

    assert_redirected_to edit_rooms_closed_url(rooms(:pets))
    assert_equal "Rooms::Closed", Room.find(rooms(:pets).id).type
  end

  test "a direct room has no access toggle to flip" do
    patch room_access_url(rooms(:david_and_kevin)), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Rooms::Direct", Room.find(rooms(:david_and_kevin).id).type
  end

  test "a forum has no access toggle to flip" do
    rooms(:help_desk).memberships.grant_to(users(:david))

    patch room_access_url(rooms(:help_desk)), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Rooms::Forum", Room.find(rooms(:help_desk).id).type
  end

  test "a chat thread has no access toggle to flip" do
    sign_in :kevin
    message = rooms(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Rooms::Thread.find_or_create_for(message, creator: users(:kevin))

    patch room_access_url(thread), params: { open: "1" }

    assert_response :forbidden
    assert_equal "Rooms::Thread", Room.find(thread.id).type
    assert_not Room.browsable_by(users(:rachel)).exists?(id: thread.id)
  end

  test "a non-member can't reach the toggle" do
    sign_in :rachel

    assert_raises ActiveRecord::RecordNotFound do
      patch room_access_url(rooms(:designers)), params: { open: "1" }
    end

    assert_equal "Rooms::Closed", Room.find(rooms(:designers).id).type
  end
end

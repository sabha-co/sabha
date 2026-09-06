require "test_helper"

# Where the unread cursor lands is decided server-side, and opening a room
# clears it (Membership.connect). Asserting it in a browser means racing that
# clear — the room render is the only moment it exists — so it is asserted on
# the response instead. Whether the cursor's row also repeats the day's date is
# a client-side rule, covered in test/system/header_stream_audit_test.rb.
class UnreadCursorRenderingTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @room = rooms(:designers)
    @first = @room.messages.create!(creator: users(:jason), body: "Audit first message",
      created_at: Time.current.change(hour: 12))
    @second = @room.messages.create!(creator: users(:jason), body: "Audit follow-on message",
      created_at: @first.created_at + 1.minute)
    @membership = @room.memberships.find_by!(user: users(:kevin))
  end

  test "the cursor renders on the first unseen message" do
    rewind_unread_to @membership, @second, marked: true
    sign_in :kevin

    get room_url(@room)

    assert_response :success
    assert_select "##{dom_id(@second)} #unread_separator"
    assert_select "##{dom_id(@first)} #unread_separator", count: 0
  end

  test "a caught-up room renders no cursor at all" do
    catch_up @membership
    sign_in :kevin

    get room_url(@room)

    assert_response :success
    assert_select "#unread_separator", count: 0
  end
end

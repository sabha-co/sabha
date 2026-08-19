require "test_helper"

class Rooms::DirectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  # ===================
  # New action tests
  # ===================

  test "new without user_ids renders the compose screen with an empty recipient picker and composer" do
    get new_rooms_direct_url
    assert_response :success
    assert_select "form.dm-new[action=?]", rooms_directs_path
    assert_select "form.dm-new select[name='user_ids[]'][multiple]"
    assert_select "form.dm-new select[name='user_ids[]'] option", count: 0
    assert_select "form.dm-new [name='message[body]']"
    assert_select ".dm-new__title", text: "Who is this for?"
  end

  test "new with user_ids pre-seeds the recipient picker and writes nothing" do
    assert_no_difference [ -> { Rooms::Direct.count }, -> { Membership.count }, -> { Message.count } ] do
      get new_rooms_direct_url(user_ids: [ users(:jz).id ])
    end

    assert_response :success
    assert_select "form.dm-new[action=?]", rooms_directs_path
    assert_select "select[name='user_ids[]'] option[value=?][selected]", users(:jz).id.to_s, text: users(:jz).name
    assert_select ".dm-new__title", text: "No messages yet"  # server renders the picked state, no flash
  end

  test "new with user_ids for an existing DM redirects to it (stale link)" do
    existing = rooms(:david_and_kevin)

    assert_no_difference -> { Rooms::Direct.count } do
      get new_rooms_direct_url(user_ids: [ users(:kevin).id ])
    end

    assert_redirected_to room_url(existing)
  end

  test "new does not push an unsolicited conversation into the recipient's sidebar" do
    jz_stream = "#{users(:jz).to_gid_param}:rooms"

    assert_broadcasts jz_stream, 0 do
      get new_rooms_direct_url(user_ids: [ users(:jz).id ])
    end
  end

  # ===================
  # Create action tests
  # ===================

  test "create materializes the DM with its first message and redirects to it" do
    assert_difference [ -> { Rooms::Direct.count }, -> { Message.count } ], 1 do
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ], message: { body: "First message" } }
    end

    room = Rooms::Direct.last
    assert_redirected_to room_url(room)
    assert room.users.include?(users(:david))
    assert room.users.include?(users(:jz))
    assert_equal "First message", room.messages.sole.plain_text_body
  end

  test "create without a message is rejected and materializes nothing" do
    # A DM only exists once someone sends a message, so create requires one.
    # (The provisional composer always sends one; a bodyless POST is malformed and
    # Rails maps ParameterMissing to a 400.)
    assert_no_difference -> { Rooms::Direct.count } do
      assert_raises ActionController::ParameterMissing do
        post rooms_directs_url, params: { user_ids: [ users(:jz).id ] }
      end
    end
  end

  test "create with a blank message materializes nothing" do
    # Messages have no body-presence validation, so a blank body would otherwise
    # leave an empty DM behind — the transaction rolls it back instead.
    assert_no_difference [ -> { Rooms::Direct.count }, -> { Message.count } ] do
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ], message: { body: "  " } }
    end

    assert_response :unprocessable_entity
  end

  test "create only materializes one room per user set" do
    assert_difference -> { Rooms::Direct.count }, +1 do
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ], message: { body: "one" } }
      post rooms_directs_url, params: { user_ids: [ users(:jz).id ], message: { body: "two" } }
    end
  end

  test "destroy only allowed for all room users" do
    sign_in :kevin

    assert_difference -> { Room.active.count }, -1 do
      delete rooms_direct_url(rooms(:david_and_kevin))
      assert_redirected_to root_url
    end
  end

  test "non-admin cannot create DM when restricted to administrators" do
    accounts(:signal).settings.restrict_direct_messages_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_rooms_direct_url
    assert_response :forbidden

    post rooms_directs_url, params: { user_ids: [ users(:david).id ], message: { body: "Hi" } }
    assert_response :forbidden
  end

  test "admin can create DM when restricted to administrators" do
    accounts(:signal).settings.restrict_direct_messages_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_rooms_direct_url
    assert_response :success

    post rooms_directs_url, params: { user_ids: [ users(:jz).id ], message: { body: "Hi" } }
    assert_redirected_to room_url(Rooms::Direct.last)
  end
end

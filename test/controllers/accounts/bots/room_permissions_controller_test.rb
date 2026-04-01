require "test_helper"

class Accounts::Bots::RoomPermissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @bot = users(:bender)
    @room = rooms(:designers)
  end

  test "show for room bot is in" do
    room = rooms(:watercooler) # bender has membership here
    get account_bot_room_permission_url(@bot, room)
    assert_response :ok
  end

  test "show for room bot is not in" do
    get account_bot_room_permission_url(@bot, @room)
    assert_response :ok
  end

  test "create adds bot to room with system message" do
    assert_difference -> { @bot.memberships.count } do
      post account_bot_room_permission_url(@bot, @room)
    end

    assert_redirected_to account_bot_room_permission_url(@bot, @room)
    assert @bot.member_of?(@room)

    system_message = @room.messages.last
    assert_match "added", system_message.body.to_plain_text
  end

  test "update changes involvement" do
    membership = @bot.memberships.find_by!(room: rooms(:watercooler))
    assert_equal "mentions", membership.involvement

    patch account_bot_room_permission_url(@bot, rooms(:watercooler)), params: { involvement: "nothing" }

    assert_redirected_to account_bot_room_permission_url(@bot, rooms(:watercooler))
    assert_equal "nothing", membership.reload.involvement
  end

  test "destroy removes bot from room with system message" do
    room = rooms(:watercooler)

    delete account_bot_room_permission_url(@bot, room)

    assert_redirected_to account_bot_room_permission_url(@bot, room)
    assert_not @bot.reload.member_of?(room)
  end

  test "requires admin" do
    sign_in :kevin
    get account_bot_room_permission_url(@bot, @room)
    assert_redirected_to root_url
  end
end

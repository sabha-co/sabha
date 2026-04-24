require "test_helper"

class API::Bots::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "list room members" do
    get api_bots_room_members_url(@room), headers: bot_headers(@bot.bot_key)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)
    assert json.any? { |m| m["id"] == @bot.id }

    member = json.first
    assert member["id"].present?
    assert member["name"].present?
    assert member["role"].present?
  end

  test "returns 404 for room bot is not a member of" do
    get api_bots_room_members_url(rooms(:designers)), headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_room_members_url(@room), headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  # Add member

  test "creator bot can add a member" do
    Current.user = @bot
    room = Rooms::Closed.create_for({ name: "Bot's Room" }, users: @bot)
    Current.reset

    post api_bots_room_members_url(room),
      params: { user_id: users(:david).id },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :created
    assert_equal users(:david).id, response.parsed_body["id"]
    assert room.users.include?(users(:david))
  end

  test "non-creator bot cannot add members" do
    post api_bots_room_members_url(@room),
      params: { user_id: users(:kevin).id },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :forbidden
  end

  test "adding nonexistent user returns 404" do
    Current.user = @bot
    room = Rooms::Closed.create_for({ name: "Bot's Room" }, users: @bot)
    Current.reset

    post api_bots_room_members_url(room),
      params: { user_id: 999999 },
      as: :json, headers: bot_headers(@bot.bot_key)

    assert_response :not_found
  end

  # Remove member

  test "creator bot can remove a member" do
    Current.user = @bot
    room = Rooms::Closed.create_for({ name: "Bot's Room" }, users: @bot)
    Current.reset
    room.add_member!(users(:david), actor: @bot)

    delete api_bots_room_member_url(room, users(:david)), headers: bot_headers(@bot)

    assert_response :no_content
    assert_not room.reload.users.include?(users(:david))
  end

  test "non-creator bot cannot remove members" do
    delete api_bots_room_member_url(@room, users(:david)), headers: bot_headers(@bot)

    assert_response :forbidden
  end

  test "cannot remove last member" do
    Current.user = @bot
    room = Rooms::Closed.create_for({ name: "Solo Bot" }, users: @bot)
    Current.reset

    delete api_bots_room_member_url(room, @bot), headers: bot_headers(@bot)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["code"]
  end
end

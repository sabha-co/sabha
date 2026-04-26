require "test_helper"

class API::Bots::Autocompletable::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "query returns visible matches" do
    get api_bots_autocompletable_users_url, params: { query: "David" }, headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert json.any? { |u| u["id"] == users(:david).id }
  end

  test "blank query is capped" do
    get api_bots_autocompletable_users_url, params: { query: "" }, headers: bot_headers(@bot)

    assert_response :success
    assert response.parsed_body.size <= 20
  end

  test "room-scoped blank query only returns members of that room" do
    other_room = Rooms::Open.create!(name: "Side Room", creator: users(:david))
    Membership.create!(user: @bot, room: other_room, involvement: :everything)
    Membership.create!(user: users(:jz), room: other_room, involvement: :everything)

    get api_bots_autocompletable_users_url, params: { room_id: @room.id }, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["id"] == users(:jz).id }, "cross-room user must not surface"
  end

  test "with room_id, 404s when bot is not a member of that room" do
    get api_bots_autocompletable_users_url, params: { room_id: rooms(:designers).id }, headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_autocompletable_users_url, headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end
end

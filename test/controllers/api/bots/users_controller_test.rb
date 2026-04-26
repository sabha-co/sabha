require "test_helper"

class API::Bots::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "index returns visible users with api fields" do
    get api_bots_users_url, headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)
    assert json.any? { |u| u["id"] == users(:david).id }

    user = json.first
    assert_equal %w[bot id name role url], user.keys.sort
    assert user["url"].include?("/users/")
  end

  test "index paginates and caps per_page" do
    get api_bots_users_url, params: { per_page: 1, page: 1 }, headers: bot_headers(@bot)
    first_page = response.parsed_body

    get api_bots_users_url, params: { per_page: 1, page: 2 }, headers: bot_headers(@bot)
    second_page = response.parsed_body

    assert_equal 1, first_page.size
    assert_equal 1, second_page.size
    assert_not_equal first_page.first["id"], second_page.first["id"]

    get api_bots_users_url, params: { per_page: 500 }, headers: bot_headers(@bot)
    assert_operator response.parsed_body.size, :<=, 100
  end

  test "index scopes to the requested room" do
    other_room = Rooms::Open.create!(name: "Side Room", creator: users(:david))
    Membership.create!(user: @bot, room: other_room, involvement: :everything)
    Membership.create!(user: users(:jz), room: other_room, involvement: :everything)

    get api_bots_users_url, params: { room_id: @room.id, per_page: 100 }, headers: bot_headers(@bot)

    json = response.parsed_body
    assert json.any? { |u| u["id"] == users(:david).id }, "watercooler member should be present"
    assert_not json.any? { |u| u["id"] == users(:jz).id }, "user from other room must not leak"
  end

  test "show returns a shared user profile" do
    get api_bots_user_url(users(:rachel)), headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert_equal users(:rachel).id, json["id"]
    assert_equal "Rachel Green", json["name"]
    assert_equal "Fashion buyer at Bloomingdale's", json["bio"]
    assert_equal "https://x.com/rachelgreen", json["twitter_url"]
    assert_equal "https://linkedin.com/in/rachelgreen", json["linkedin_url"]
    assert_equal "https://rachelgreen.com", json["personal_url"]
  end

  test "show returns 404 for a user outside the bot's shared rooms" do
    stranger = users(:jz)
    assert_not @room.users.include?(stranger)

    get api_bots_user_url(stranger), headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "index with room_id 404s when bot is not a member of that room" do
    get api_bots_users_url, params: { room_id: rooms(:designers).id }, headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "show with room_id 404s for users not in that room" do
    other_room = Rooms::Open.create!(name: "Side Room", creator: users(:david))
    Membership.create!(user: @bot, room: other_room, involvement: :everything)
    Membership.create!(user: users(:jz), room: other_room, involvement: :everything)

    get api_bots_user_url(users(:jz), room_id: @room.id), headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_users_url, headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end
end

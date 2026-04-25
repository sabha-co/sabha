require "test_helper"

class API::Bots::Autocompletable::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
    [ users(:rachel), users(:kevin) ].each do |user|
      Membership.create!(user: user, room: @room, involvement: :everything) unless @room.users.include?(user)
    end
  end

  test "matches by first name" do
    get api_bots_autocompletable_users_url, params: { query: "David" }, headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert json.any? { |u| u["id"] == users(:david).id }
  end

  test "matches by partial name" do
    get api_bots_autocompletable_users_url, params: { query: "rach" }, headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert json.any? { |u| u["id"] == users(:rachel).id }
  end

  test "exact first-name match ranks before partial matches" do
    davidson = User.create!(name: "Davidson", email_address: "davidson@example.com", verified_at: 1.day.ago)
    Membership.create!(user: davidson, room: @room, involvement: :everything)

    get api_bots_autocompletable_users_url, params: { query: "David" }, headers: bot_headers(@bot)

    ids = response.parsed_body.map { |u| u["id"] }
    david_pos = ids.index(users(:david).id)
    davidson_pos = ids.index { |id| User.find(id).name == "Davidson" }
    assert david_pos.present? && davidson_pos.present?
    assert david_pos < davidson_pos, "exact first-name match should rank before partial"
  end

  test "blank query returns recent posters" do
    get api_bots_autocompletable_users_url, headers: bot_headers(@bot)

    assert_response :success
    assert response.parsed_body.is_a?(Array)
  end

  test "caps at 20 results" do
    get api_bots_autocompletable_users_url, params: { query: "" }, headers: bot_headers(@bot)

    assert_response :success
    assert response.parsed_body.size <= 20
  end

  test "excludes deactivated users" do
    users(:rachel).update!(status: :deactivated)

    get api_bots_autocompletable_users_url, params: { query: "rach" }, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["id"] == users(:rachel).id }
  end

  test "excludes default-named users" do
    User.create!(name: User::DEFAULT_NAME, email_address: "placeholder@example.com")

    get api_bots_autocompletable_users_url, params: { query: User::DEFAULT_NAME.split.first }, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["name"] == User::DEFAULT_NAME }
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_autocompletable_users_url, headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  test "excludes users from rooms the bot is not in" do
    stranger = users(:jz)
    assert_not @room.users.include?(stranger)

    get api_bots_autocompletable_users_url, params: { query: stranger.name }, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["id"] == stranger.id }
  end
end

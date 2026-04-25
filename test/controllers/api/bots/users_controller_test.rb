require "test_helper"

class API::Bots::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  # Index

  test "lists active users" do
    get api_bots_users_url, headers: bot_headers(@bot)

    assert_response :success
    json = response.parsed_body
    assert json.is_a?(Array)
    assert json.any? { |u| u["id"] == users(:david).id }

    user = json.first
    assert user["id"].present?
    assert user["name"].present?
    assert user.key?("role")
    assert user.key?("bot")
    assert user["url"].include?("/users/")
  end

  test "index includes bots and humans" do
    get api_bots_users_url, headers: bot_headers(@bot)

    json = response.parsed_body
    assert json.any? { |u| u["bot"] == true }
    assert json.any? { |u| u["bot"] == false }
  end

  test "index orders administrators before regular members" do
    get api_bots_users_url, headers: bot_headers(@bot)

    roles = response.parsed_body.map { |u| u["role"] }
    admin_first = roles.index("administrator")
    member_first = roles.index("member")
    assert admin_first.present? && member_first.present?
    assert admin_first < member_first, "administrators should sort before members"
  end

  test "index excludes default-named users" do
    User.create!(name: User::DEFAULT_NAME, email_address: "placeholder@example.com")

    get api_bots_users_url, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["name"] == User::DEFAULT_NAME }
  end

  test "index excludes deactivated users" do
    users(:david).update!(status: :deactivated)

    get api_bots_users_url, headers: bot_headers(@bot)

    json = response.parsed_body
    assert_not json.any? { |u| u["id"] == users(:david).id }
  end

  test "index respects per_page" do
    get api_bots_users_url, params: { per_page: 1 }, headers: bot_headers(@bot)

    assert_response :success
    assert_equal 1, response.parsed_body.size
  end

  test "index paginates with page param" do
    get api_bots_users_url, params: { per_page: 1, page: 1 }, headers: bot_headers(@bot)
    first_page = response.parsed_body

    get api_bots_users_url, params: { per_page: 1, page: 2 }, headers: bot_headers(@bot)
    second_page = response.parsed_body

    assert_not_equal first_page.first["id"], second_page.first["id"]
  end

  test "index caps per_page at 100" do
    get api_bots_users_url, params: { per_page: 500 }, headers: bot_headers(@bot)

    assert_response :success
    assert response.parsed_body.size <= 100
  end

  test "invalid bot key redirects to sign in" do
    get api_bots_users_url, headers: bot_headers("999-invalid")

    assert_redirected_to new_session_url
  end

  # Show

  test "shows a user with profile fields" do
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

  test "show returns 404 for missing user" do
    get api_bots_user_url(id: 999_999), headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "show returns 404 for deactivated user" do
    users(:david).update!(status: :deactivated)

    get api_bots_user_url(users(:david)), headers: bot_headers(@bot)

    assert_response :not_found
  end

  test "show returns 404 for default-named placeholder user" do
    placeholder = User.create!(name: User::DEFAULT_NAME, email_address: "placeholder@example.com")

    get api_bots_user_url(placeholder), headers: bot_headers(@bot)

    assert_response :not_found
  end
end

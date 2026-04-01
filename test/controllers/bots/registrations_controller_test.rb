require "test_helper"

class Bots::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @join_code = account_join_codes(:signal)
    @account = accounts(:signal)
    @account.update!(settings: { "allow_bot_self_registration" => "true" })
  end

  test "successful bot registration returns 201 with bot_key and rooms" do
    assert_difference "User.count", 1 do
      post join_bot_url(@join_code.code),
        params: { name: "TestBot", webhook_url: "https://example.com/hook" },
        as: :json
    end

    assert_response :created
    json = response.parsed_body

    assert json["bot_key"].present?
    assert_equal "TestBot", json["name"]
    assert_equal "https://example.com/hook", json["webhook_url"]
    assert json["rooms"].is_a?(Array)

    bot = User.find_by(name: "TestBot")
    assert bot.bot?
    assert_equal "https://example.com/hook", bot.webhook_url
  end

  test "registration redeems join code" do
    assert_difference -> { @join_code.reload.usage_count }, 1 do
      post join_bot_url(@join_code.code),
        params: { name: "CountBot" },
        as: :json
    end

    assert_response :created
  end

  test "returns 403 when bot self-registration is disabled" do
    @account.update!(settings: { "allow_bot_self_registration" => "false" })

    post join_bot_url(@join_code.code),
      params: { name: "Blocked" },
      as: :json

    assert_response :forbidden
    json = response.parsed_body
    assert_equal "self_registration_disabled", json["code"]
  end

  test "returns 404 for invalid join code" do
    post join_bot_url("INVALID-CODE"),
      params: { name: "Lost" },
      as: :json

    assert_response :not_found
    json = response.parsed_body
    assert_equal "join_code_not_found", json["code"]
  end

  test "returns 410 for expired join code" do
    @join_code.update_columns(expires_at: 1.day.ago)

    post join_bot_url(@join_code.code),
      params: { name: "Late" },
      as: :json

    assert_response :gone
    json = response.parsed_body
    assert_equal "join_code_expired", json["code"]
  end

  test "returns 410 for usage-exhausted join code" do
    @join_code.update_columns(usage_limit: 1, usage_count: 1)

    post join_bot_url(@join_code.code),
      params: { name: "TooMany" },
      as: :json

    assert_response :gone
    json = response.parsed_body
    assert_equal "join_code_expired", json["code"]
  end

  test "registration with legacy mentions_url param" do
    post join_bot_url(@join_code.code),
      params: { name: "DualBot", mentions_url: "https://example.com/mentions" },
      as: :json

    assert_response :created
    json = response.parsed_body
    assert_equal "https://example.com/mentions", json["webhook_url"]
  end

  test "registration without name uses default" do
    post join_bot_url(@join_code.code),
      params: {},
      as: :json

    assert_response :created
    json = response.parsed_body
    assert json["name"].present?
  end

  test "HTML request falls through to UsersController" do
    get join_url(@join_code.code)
    assert_response :success
    assert_includes response.body, "html"
  end

  test "rooms in response exclude threads" do
    post join_bot_url(@join_code.code),
      params: { name: "ThreadBot" },
      as: :json

    assert_response :created
    json = response.parsed_body
    room_types = json["rooms"].map { |r| r["type"] }
    assert_not_includes room_types, "Thread"
  end

  test "all error responses include code field" do
    @account.update!(settings: { "allow_bot_self_registration" => "false" })

    post join_bot_url(@join_code.code), params: { name: "X" }, as: :json
    assert response.parsed_body["code"].present?

    @account.update!(settings: { "allow_bot_self_registration" => "true" })

    post join_bot_url("BAD-CODE"), params: { name: "X" }, as: :json
    assert response.parsed_body["code"].present?
  end
end

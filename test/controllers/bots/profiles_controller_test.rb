require "test_helper"

class Bots::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
  end

  test "updates bot name" do
    patch bot_profile_url(@bot.bot_key),
      params: { name: "Renamed Bot" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert_equal "Renamed Bot", json["name"]
    assert_equal "Renamed Bot", @bot.reload.name
  end

  test "updates mentions_url" do
    patch bot_profile_url(@bot.bot_key),
      params: { mentions_url: "http://example.com/new-hook" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert_equal "http://example.com/new-hook", json["webhooks"]["mentions_url"]
    assert_equal "http://example.com/new-hook", @bot.reload.mentions_url
  end

  test "updates everything_url" do
    patch bot_profile_url(@bot.bot_key),
      params: { everything_url: "http://example.com/new-all" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert_equal "http://example.com/new-all", json["webhooks"]["everything_url"]
  end

  test "response includes name and webhooks" do
    patch bot_profile_url(@bot.bot_key),
      params: { name: "Check" },
      as: :json

    assert_response :success
    json = response.parsed_body
    assert json.key?("name")
    assert json.key?("webhooks")
    assert json["webhooks"].key?("mentions_url")
    assert json["webhooks"].key?("everything_url")
  end

  test "invalid bot key redirects to sign in" do
    patch bot_profile_url("999-invalidtoken"),
      params: { name: "Nope" },
      as: :json

    assert_redirected_to new_session_url
  end
end

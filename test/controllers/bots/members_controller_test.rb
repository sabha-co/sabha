require "test_helper"

class Bots::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "list room members" do
    get room_bot_members_url(@room, @bot.bot_key)

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
    get room_bot_members_url(rooms(:designers), @bot.bot_key)

    assert_response :not_found
  end

  test "invalid bot key redirects to sign in" do
    get room_bot_members_url(@room, "999-invalid")

    assert_redirected_to new_session_url
  end
end

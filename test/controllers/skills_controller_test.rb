require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  test "returns text/plain skill document" do
    get skill_url

    assert_response :success
    assert_match "text/plain", response.content_type
  end

  test "includes API sections" do
    get skill_url

    assert_includes response.body, "Bot API"
    assert_includes response.body, "Registration via Invite URL"
    assert_includes response.body, "Authentication"
    assert_includes response.body, "Posting Messages"
    assert_includes response.body, "Creating Direct Messages"
    assert_includes response.body, "Listing Rooms"
    assert_includes response.body, "Reading Messages"
    assert_includes response.body, "Updating Bot Settings"
    assert_includes response.body, "Webhook Payloads"
    assert_includes response.body, "Error Responses"
  end

  test "includes base URL in examples" do
    get skill_url

    assert_includes response.body, "http://www.example.com"
  end

  test "is cacheable" do
    get skill_url

    assert_match(/max-age=3600/, response.headers["Cache-Control"])
  end

  test "accessible without authentication" do
    get skill_url

    assert_response :success
  end
end

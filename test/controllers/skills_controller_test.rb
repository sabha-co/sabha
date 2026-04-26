require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  test "returns a public text skill document" do
    get skill_url

    assert_response :success
    assert_match "text/plain", response.content_type
    assert_includes response.body, "Bot API"
    assert_includes response.body, "Authentication"
    assert_includes response.body, "http://www.example.com"
  end

  test "is cacheable" do
    get skill_url

    assert_match(/max-age=3600/, response.headers["Cache-Control"])
  end
end

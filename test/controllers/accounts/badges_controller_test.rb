require "test_helper"

class Accounts::BadgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index badges" do
    get account_badges_url
    assert_response :success
  end

  test "non-admins cannot index badges" do
    sign_in :kevin
    get account_badges_url
    assert_redirected_to root_path
  end

  test "create badge" do
    assert_difference -> { Badge.count }, 1 do
      post account_badges_url, params: { badge: { name: "New", color: "#FF0000" } }
    end

    assert_redirected_to account_badges_url
    assert_equal "New", Badge.last.name
    assert_equal "#FF0000", Badge.last.color
  end

  test "create badge with invalid params" do
    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "", color: "#FF0000" } }
    end

    assert_redirected_to account_badges_url
  end

  test "create badge with invalid color format" do
    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "Test", color: "red" } }
    end

    assert_redirected_to account_badges_url
  end

  test "destroy badge" do
    badge = badges(:staff)

    assert_difference -> { Badge.count }, -1 do
      delete account_badge_url(badge)
    end

    assert_redirected_to account_badges_url
  end

  test "non-admins cannot create badges" do
    sign_in :kevin

    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "Hack", color: "#000" } }
    end

    assert_redirected_to root_path
  end

  test "non-admins cannot destroy badges" do
    sign_in :kevin

    assert_no_difference -> { Badge.count } do
      delete account_badge_url(badges(:founder))
    end

    assert_redirected_to root_path
  end
end

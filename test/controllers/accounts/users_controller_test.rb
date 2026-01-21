require "test_helper"

class Accounts::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index lists users grouped by role" do
    get account_users_url
    assert_response :success
  end

  test "index search finds users by name" do
    get account_users_url, params: { query: "Dav" }
    assert_response :success
    assert_select "turbo-frame#user_#{users(:david).id}"
    assert_select "turbo-frame#user_#{users(:kevin).id}", count: 0
  end

  test "index search returns no results for non-matching query" do
    get account_users_url, params: { query: "nonexistent" }
    assert_response :success
    assert_select "p", text: "No members found"
  end

  test "update role" do
    user = users(:kevin)
    assert user.member?

    patch account_user_url(user), params: { user: { role: "moderator" } }

    assert_redirected_to account_users_url
    assert user.reload.moderator?
  end

  test "update role to administrator" do
    user = users(:kevin)

    patch account_user_url(user), params: { user: { role: "administrator" } }

    assert_redirected_to account_users_url
    assert user.reload.administrator?
  end

  test "update role rejects invalid roles" do
    user = users(:kevin)

    patch account_user_url(user), params: { user: { role: "superuser" } }

    assert_redirected_to account_users_url
    assert user.reload.member?
  end

  test "update role rejects bot role" do
    user = users(:kevin)

    patch account_user_url(user), params: { user: { role: "bot" } }

    assert_redirected_to account_users_url
    assert user.reload.member?
  end

  test "assign badge to user" do
    user = users(:kevin)
    badge = badges(:staff)

    assert_nil user.badge

    patch account_user_url(user), params: { user: { badge_id: badge.id } }

    assert_equal badge, user.reload.badge
  end

  test "change user badge" do
    user = users(:david)
    new_badge = badges(:vip)

    assert_equal badges(:founder), user.badge

    patch account_user_url(user), params: { user: { badge_id: new_badge.id } }

    assert_equal new_badge, user.reload.badge
  end

  test "remove badge from user" do
    user = users(:david)
    assert user.badge.present?

    patch account_user_url(user), params: { user: { badge_id: "" } }

    assert_nil user.reload.badge
  end

  test "destroy deactivates user" do
    user = users(:kevin)

    assert_difference -> { User.active.count }, -1 do
      delete account_user_url(user)
    end

    assert_redirected_to account_users_url
    assert user.reload.deactivated?
  end

  test "non-admins cannot access index" do
    sign_in :kevin

    get account_users_url
    assert_redirected_to root_path
  end

  test "non-admins cannot update users" do
    sign_in :kevin

    patch account_user_url(users(:jz)), params: { user: { role: "administrator" } }
    assert_redirected_to root_path
  end

  test "non-admins cannot destroy users" do
    sign_in :kevin

    delete account_user_url(users(:jz))
    assert_redirected_to root_path
  end
end

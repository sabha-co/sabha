require "test_helper"

class Accounts::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index lists users grouped by role" do
    get account_users_url
    assert_response :success
  end

  test "index renders as the Members pane in the settings shell" do
    get account_users_url

    assert_select ".settings-nav__item[aria-current=page]", text: "Members"
    assert_select ".settings-header__title", text: "Members"
    assert_select ".navbar-title", text: "Settings"
    assert_select ".members-page .members-toolbar input[name=query]"
    assert_select "#administrators_section.role-section"
  end

  test "index hides the badges link from non-admins" do
    sign_in :kevin
    get account_users_url

    assert_response :success
    assert_select ".settings-nav__item", text: "Badges", count: 0
    assert_match users(:david).name, response.body
    assert_match users(:jason).name, response.body
  end

  test "edit renders the manage-member dialog content" do
    get edit_account_user_url(users(:kevin))

    assert_response :success
    assert_select "turbo-frame#manage_member" do
      assert_select ".role-option", count: 3
      assert_select ".role-option--current", text: /Member/
      assert_select ".badge-chip", text: "Founder"
      assert_select "button", text: "Deactivate"
      assert_select "button", text: /Ban/
    end
  end

  test "edit omits deactivation for yourself" do
    get edit_account_user_url(users(:david))

    assert_response :success
    assert_select "button", text: "Deactivate", count: 0
  end

  test "edit is refused for non-admins" do
    sign_in :kevin

    get edit_account_user_url(users(:jz))

    assert_response :forbidden
    assert_select ".empty-state__title", text: "Administrators only"
    assert_select "a[href=?]", account_path, text: "Back to community settings"
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
    assert_select ".empty-state__title", text: "No one matches “nonexistent”"
  end

  test "staff search finds deactivated and banned users" do
    deactivated = users(:jz)
    deactivated.deactivate
    banned = users(:rachel)
    banned.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    banned.ban

    get account_users_url, params: { query: "JZ" }
    assert_select "turbo-frame#user_#{deactivated.id}"

    get account_users_url, params: { query: "Rachel" }
    assert_select "turbo-frame#user_#{banned.id}"
  end

  test "empty deactivated filter still shows All chip so staff can navigate back" do
    assert_equal 0, User.without_bots.deactivated.count

    get account_users_url(status: "deactivated")

    assert_response :success
    assert_select ".member-status-tab", text: "All"
    assert_select ".member-status-tab--active", text: "Deactivated (0)"
  end

  test "empty banned filter still shows All chip so staff can navigate back" do
    assert_equal 0, User.without_bots.banned.count

    get account_users_url(status: "banned")

    assert_response :success
    assert_select ".member-status-tab", text: "All"
    assert_select ".member-status-tab--active", text: "Banned (0)"
  end

  test "non-staff search hides deactivated and banned users" do
    deactivated = users(:jz)
    deactivated.deactivate
    banned = users(:rachel)
    banned.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    banned.ban

    sign_in :kevin

    get account_users_url, params: { query: "JZ" }
    assert_select "turbo-frame#user_#{deactivated.id}", count: 0

    get account_users_url, params: { query: "Rachel" }
    assert_select "turbo-frame#user_#{banned.id}", count: 0
  end

  test "update role" do
    user = users(:kevin)
    assert user.member?

    patch account_user_url(user), params: { user: { role: "moderator" } }

    assert_redirected_to account_users_url
    assert user.reload.moderator?
  end

  test "update role rejects invalid roles" do
    user = users(:kevin)

    patch account_user_url(user), params: { user: { role: "superuser" } }

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

  test "destroy rejects an admin trying to deactivate themselves" do
    sign_in :david
    me = users(:david)

    delete account_user_url(me)

    assert_redirected_to account_users_url
    assert_equal "You can't deactivate yourself.", flash[:alert]
    assert me.reload.active?
  end

  test "destroy deactivates user" do
    user = users(:kevin)

    assert_difference -> { User.active.count }, -1 do
      delete account_user_url(user)
    end

    assert_redirected_to account_users_url
    assert user.reload.deactivated?
  end

  test "non-admins cannot access deactivated filter" do
    sign_in :kevin

    get account_users_url(status: "deactivated")
    assert_response :success
    assert_select ".role-section__heading", text: "Deactivated", count: 0
  end

  test "non-admins cannot access banned filter" do
    sign_in :kevin

    get account_users_url(status: "banned")
    assert_response :success
    assert_select ".role-section__heading", text: "Banned", count: 0
  end

  test "non-admins cannot update users" do
    sign_in :kevin

    patch account_user_url(users(:jz)), params: { user: { role: "administrator" } }
    assert_response :forbidden
  end

  test "non-admins cannot destroy users" do
    sign_in :kevin

    delete account_user_url(users(:jz))
    assert_response :forbidden
  end

  test "index shows deactivated users when filtering by status" do
    user = users(:kevin)
    user.deactivate

    get account_users_url(status: "deactivated")

    assert_response :success
    assert_select "turbo-frame#user_#{user.id}"
  end

  test "reactivate restores deactivated user" do
    user = users(:kevin)
    user.deactivate

    assert user.reload.deactivated?

    post account_user_reactivation_url(user)

    assert_redirected_to account_users_url
    assert user.reload.active?
  end

  test "non-admins cannot reactivate users" do
    sign_in :kevin

    user = users(:jz)
    user.deactivate

    post account_user_reactivation_url(user)

    assert_response :forbidden
    assert user.reload.deactivated?
  end

  test "reactivate does not work on banned users" do
    user = users(:kevin)
    user.sessions.create!(ip_address: "203.0.113.1", user_agent: "Test")
    user.ban

    assert user.reload.banned?

    post account_user_reactivation_url(user)

    assert_redirected_to account_users_url
    assert user.reload.banned?, "Banned user should not be reactivated via reactivate action"
  end

  test "reactivate does not work on active users" do
    user = users(:kevin)

    assert user.active?

    post account_user_reactivation_url(user)

    assert_redirected_to account_users_url
    assert user.reload.active?
  end
end

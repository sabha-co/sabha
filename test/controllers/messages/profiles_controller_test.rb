require "test_helper"

class Messages::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "show offers Edit profile on your own quick profile, not Direct message" do
    sign_in :david
    get mention_profile_url(users(:david))

    assert_response :ok
    assert_select ".quick-profile a[href=?]", user_profile_path, text: /Edit profile/
    assert_select ".quick-profile", text: /Direct message/, count: 0
  end

  test "show keeps another user's quick profile free of the Edit profile action" do
    sign_in :david
    get mention_profile_url(users(:jason))

    assert_response :ok
    assert_select ".quick-profile a[href=?]", user_profile_path, count: 0
    assert_select ".quick-profile a", text: /View profile/
  end

  test "show gives an active quick profile its status subline and card structure" do
    sign_in :david
    user = users(:jz)
    user.update! last_active_at: Time.current

    get mention_profile_url(user)

    assert_response :ok
    assert_select ".quick-profile__status", text: "Active"
    assert_select ".quick-profile__bio", text: "Designer"
    assert_select ".quick-profile__stats"
    assert_select ".quick-profile__actions"
  end
end

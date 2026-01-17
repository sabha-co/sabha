require "test_helper"

class Users::InviteLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create personal invite link" do
    users(:david).join_codes.destroy_all

    assert_difference -> { users(:david).join_codes.count }, 1 do
      post user_invite_link_url
    end

    join_code = users(:david).reload.join_codes.last
    assert join_code.personal?
    assert join_code.expires_at.present?
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_EXPIRATION.from_now + 1.second
  end

  test "regenerate destroys existing personal invite links" do
    existing_code = account_join_codes(:signal_personal)
    assert_equal users(:david), existing_code.user

    assert_no_difference -> { Account::JoinCode.count } do
      post user_invite_link_url
    end

    refute Account::JoinCode.exists?(existing_code.id)
    assert users(:david).join_codes.active.exists?
  end

  test "create responds with turbo stream" do
    post user_invite_link_url, as: :turbo_stream

    assert_response :success
    assert_match /turbo-stream/, response.body
    assert_match /invite_link/, response.body
  end

  test "create responds with redirect for html" do
    users(:david).join_codes.destroy_all

    post user_invite_link_url

    assert_redirected_to user_profile_path
  end

  test "cannot create invite link when disabled" do
    accounts(:signal).settings.allow_users_to_create_invite_links = false
    accounts(:signal).save!

    assert_no_difference -> { Account::JoinCode.count } do
      post user_invite_link_url
    end

    assert_redirected_to user_profile_path
  end

  test "can create invite link when enabled" do
    accounts(:signal).settings.allow_users_to_create_invite_links = true
    accounts(:signal).save!
    users(:david).join_codes.destroy_all

    assert_difference -> { users(:david).join_codes.count }, 1 do
      post user_invite_link_url
    end
  end
end

require "test_helper"

class Users::PresencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @user = users(:david)
  end

  test "setting each state" do
    User.presences.each_key do |state|
      patch user_presence_url, params: { user: { presence: state } }

      assert_redirected_to root_url
      assert_equal state, @user.reload.presence
    end
  end

  test "an unknown state is rejected rather than stored" do
    @user.update! presence: :away

    patch user_presence_url, params: { user: { presence: "on_holiday" } }

    assert_response :unprocessable_entity
    assert_equal "away", @user.reload.presence
  end

  test "a missing presence is rejected" do
    patch user_presence_url, params: { user: { name: "Hacked" } }

    assert_response :unprocessable_entity
  end

  # The route has no id, so the only defence that matters is that nothing else
  # rides along in the same payload.
  test "other attributes in the same request are ignored" do
    patch user_presence_url, params: { user: { presence: "away", name: "Hacked", role: "administrator" } }

    assert_equal "away", @user.reload.presence
    assert_equal "David", @user.name
  end

  test "changing presence counts as activity" do
    @user.update! last_active_at: 30.minutes.ago

    patch user_presence_url, params: { user: { presence: "available" } }

    assert @user.reload.active_now?, "the chooser would otherwise be broadcast as idle"
  end

  test "the change is broadcast on the workspace presence stream" do
    assert_broadcasts "#{Current.account.to_gid_param}:presence", 1 do
      patch user_presence_url, params: { user: { presence: "away" } }
    end
  end

  test "signing out blocks the update" do
    delete session_url

    patch user_presence_url, params: { user: { presence: "away" } }

    assert_response :redirect
    assert_equal "available", @user.reload.presence
  end
end

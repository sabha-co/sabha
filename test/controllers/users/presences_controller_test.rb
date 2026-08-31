require "test_helper"

class Users::PresencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @user = users(:david)
  end

  test "setting each state" do
    User.availabilities.each_key do |state|
      patch user_presence_url, params: { user: { availability: state } }

      assert_redirected_to root_url
      assert_equal state, @user.reload.availability
    end
  end

  test "an unknown state is rejected rather than stored" do
    @user.update! availability: :away

    patch user_presence_url, params: { user: { availability: "on_holiday" } }

    assert_response :unprocessable_entity
    assert_equal "away", @user.reload.availability
  end

  test "a missing availability is rejected" do
    patch user_presence_url, params: { user: { name: "Hacked" } }

    assert_response :unprocessable_entity
  end

  # The route has no id, so the only defence that matters is that nothing else
  # rides along in the same payload.
  test "other attributes in the same request are ignored" do
    patch user_presence_url, params: { user: { availability: "away", name: "Hacked", role: "administrator" } }

    assert_equal "away", @user.reload.availability
    assert_equal "David", @user.name
  end

  test "changing presence counts as activity" do
    @user.update! last_active_at: 30.minutes.ago

    patch user_presence_url, params: { user: { availability: "available" } }

    assert @user.reload.interacted_recently?, "the chooser would otherwise be broadcast as idle"
  end

  test "the change is broadcast to a DM partner and to the workspace stream" do
    assert_broadcasts broadcasting_for(users(:jason), :presence), 1 do
      assert_broadcasts broadcasting_for(Current.account, :presence), 1 do
        patch user_presence_url, params: { user: { availability: "away" } }
      end
    end
  end

  # A dot that turns amber beside words still reading "Active" is worse than
  # one that never moved, so the surfaces that spell the state out are replayed
  # alongside it rather than left for the next full page load. Asserted on both
  # payloads, since the surfaces are split across two audiences.
  test "the words beside the dot travel with it" do
    patch user_presence_url, params: { user: { availability: "away" } }

    assert_rendered_turbo_stream_broadcast users(:jason), :presence,
      action: :replace, target: [ @user, :presence_dot_nav ]
    assert_rendered_turbo_stream_broadcast users(:jason), :presence,
      action: :replace, target: [ @user, :presence_label_nav ]

    assert_rendered_turbo_stream_broadcast Current.account, :presence,
      action: :replace, target: [ @user, :presence_dot_member ]
    assert_rendered_turbo_stream_broadcast Current.account, :presence,
      action: :replace, target: [ @user, :presence_label_member ]
  end

  # The presence broadcast moves the dots but never the picker itself, so the
  # turbo_stream response refreshes the picker's checked state directly —
  # otherwise its checkmark would keep pointing at the state you just left.
  test "the turbo_stream response refreshes the picker's checked state" do
    patch user_presence_url, params: { user: { availability: "away" } }, as: :turbo_stream

    assert_response :success
    assert_match %r{turbo-stream action="replace" target="presence_picker"}, response.body
    assert_select "input[type=radio][value=away][checked]"
    assert_select "input[type=radio][value=available]:not([checked])"
  end

  test "signing out blocks the update" do
    delete session_url

    patch user_presence_url, params: { user: { availability: "away" } }

    assert_response :redirect
    assert_equal "available", @user.reload.availability
  end
end

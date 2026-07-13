require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # The layout mixes this in; the bare helper test harness doesn't, so the
  # tokenless fallback branch needs it explicitly.
  include ActionCable::Helpers::ActionCableHelper

  # The cable meta tag carries a signed JWT identity so anycable-go can
  # identify the socket in Go and skip the Rails connect RPC.
  test "signed_action_cable_meta_tag mints a verifiable JWT identity for the current user" do
    Current.user = users(:david)

    html = signed_action_cable_meta_tag
    token = html[/[?&]jid=([^"&]+)/, 1]

    assert token, "expected a jid identity param on the cable meta tag"
    assert_equal users(:david), AnyCable::JWT.decode(token)[:current_user]
  ensure
    Current.reset
  end

  test "signed_action_cable_meta_tag signs with the client-facing secret, rejected under a wrong key" do
    Current.user = users(:david)

    token = signed_action_cable_meta_tag[/[?&]jid=([^"&]+)/, 1]

    assert_raises(AnyCable::JWT::VerificationError) do
      AnyCable::JWT.decode(token, secret_key: "not-the-secret")
    end
  ensure
    Current.reset
  end

  test "signed_action_cable_meta_tag falls back to a tokenless tag with no current user" do
    Current.reset

    html = signed_action_cable_meta_tag

    assert_match "action-cable-url", html
    assert_no_match(/jid=/, html, "a tokenless page must not carry a JWT identity")
  end
end

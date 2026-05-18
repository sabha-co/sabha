require "test_helper"

class SingleSignOnNonceTest < ActiveSupport::TestCase
  test "issue and consume returns stored return path" do
    session = {}
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")

    assert_equal "/rooms/general", SingleSignOnNonce.consume!(nonce, session:)
    assert SingleSignOnNonce.find_by(nonce:).used?
    assert_nil session[SingleSignOnNonce.session_key(nonce)]
  end

  test "second consume raises replayed" do
    session = {}
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")

    SingleSignOnNonce.consume!(nonce, session:)

    assert_raises SingleSignOnNonce::Replayed do
      SingleSignOnNonce.consume!(nonce, session:)
    end
  end

  test "expired nonce raises invalid" do
    session = {}
    now = Time.zone.local(2026, 5, 18, 12, 0, 0)
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general", now:)

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nonce, session:, now: now + 31.minutes)
    end
  end

  test "nonce from another session raises invalid without consuming record" do
    session = {}
    other_session = {}
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nonce, session: other_session)
    end

    assert_not SingleSignOnNonce.find_by(nonce:).used?
  end
end

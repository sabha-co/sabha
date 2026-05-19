require "test_helper"

class SingleSignOnNonceTest < ActiveSupport::TestCase
  test "issue and consume returns stored return path" do
    session = {}
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")

    assert_equal "/rooms/general", SingleSignOnNonce.consume!(nonce, session:)
    assert SingleSignOnNonce.find_by(nonce:).used?
    assert_nil session[SingleSignOnNonce::SESSION_KEY]
  end

  test "second consume raises replayed" do
    session = {}
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")

    SingleSignOnNonce.consume!(nonce, session:)

    assert_raises SingleSignOnNonce::Replayed do
      SingleSignOnNonce.consume!(nonce, session:)
    end
  end

  test "expired nonce raises invalid without mutating session" do
    session = {}
    now = Time.zone.local(2026, 5, 18, 12, 0, 0)
    nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general", now:)

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nonce, session:, now: now + 31.minutes)
    end

    assert_equal nonce, session[SingleSignOnNonce::SESSION_KEY]
    assert_not SingleSignOnNonce.find_by(nonce:).used?
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

  test "blank nonce raises invalid" do
    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nil, session: { SingleSignOnNonce::SESSION_KEY => "abc" })
    end

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!("", session: { SingleSignOnNonce::SESSION_KEY => "abc" })
    end
  end

  test "issuing a new nonce overwrites the previous session slot" do
    session = {}
    first_nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/general")
    second_nonce = SingleSignOnNonce.issue!(session:, return_path: "/rooms/random")

    assert_equal second_nonce, session[SingleSignOnNonce::SESSION_KEY]

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(first_nonce, session:)
    end

    assert_equal "/rooms/random", SingleSignOnNonce.consume!(second_nonce, session:)
  end

  test "purge_expired deletes only expired rows" do
    fresh = SingleSignOnNonce.create!(return_path: "/", expires_at: 5.minutes.from_now)
    stale = SingleSignOnNonce.create!(return_path: "/", expires_at: 1.minute.ago)

    SingleSignOnNonce.purge_expired

    assert SingleSignOnNonce.exists?(fresh.id)
    assert_not SingleSignOnNonce.exists?(stale.id)
  end
end

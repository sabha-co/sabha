require "test_helper"

class SingleSignOnNonceTest < ActiveSupport::TestCase
  test "issue and consume returns stored return path" do
    nonce = SingleSignOnNonce.issue!(return_path: "/rooms/general")

    assert_equal "/rooms/general", SingleSignOnNonce.consume!(nonce)
    assert SingleSignOnNonce.find_by(nonce:).used?
  end

  test "second consume raises replayed" do
    nonce = SingleSignOnNonce.issue!(return_path: "/rooms/general")

    SingleSignOnNonce.consume!(nonce)

    assert_raises SingleSignOnNonce::Replayed do
      SingleSignOnNonce.consume!(nonce)
    end
  end

  test "expired nonce raises invalid without consuming record" do
    now = Time.zone.local(2026, 5, 18, 12, 0, 0)
    nonce = SingleSignOnNonce.issue!(return_path: "/rooms/general", now:)

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nonce, now: now + 31.minutes)
    end

    assert_not SingleSignOnNonce.find_by(nonce:).used?
  end

  test "unknown nonce raises invalid" do
    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!("does-not-exist")
    end
  end

  test "blank nonce raises invalid" do
    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!(nil)
    end

    assert_raises SingleSignOnNonce::Invalid do
      SingleSignOnNonce.consume!("")
    end
  end

  test "purge_expired deletes only expired rows" do
    fresh = SingleSignOnNonce.create!(return_path: "/", expires_at: 5.minutes.from_now)
    stale = SingleSignOnNonce.create!(return_path: "/", expires_at: 1.minute.ago)

    SingleSignOnNonce.purge_expired

    assert SingleSignOnNonce.exists?(fresh.id)
    assert_not SingleSignOnNonce.exists?(stale.id)
  end
end

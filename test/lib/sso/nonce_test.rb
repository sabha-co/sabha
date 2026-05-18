require "test_helper"

class Sso::NonceTest < ActiveSupport::TestCase
  test "issue and consume returns stored return path" do
    active_store = {}
    used_store = {}

    nonce = Sso::Nonce.issue(active_store, return_path: "/rooms/general")

    assert_equal "/rooms/general", Sso::Nonce.consume!(active_store:, used_store:, nonce:)
    assert_nil active_store[Sso::Nonce.active_key(nonce)]
    assert used_store[Sso::Nonce.used_key(nonce)].present?
  end

  test "second consume raises replayed" do
    active_store = {}
    used_store = {}
    nonce = Sso::Nonce.issue(active_store, return_path: "/rooms/general")

    Sso::Nonce.consume!(active_store:, used_store:, nonce:)

    assert_raises Sso::Nonce::Replayed do
      Sso::Nonce.consume!(active_store:, used_store:, nonce:)
    end
  end

  test "expired nonce raises invalid" do
    active_store = {}
    used_store = {}
    now = Time.zone.local(2026, 5, 18, 12, 0, 0)
    nonce = Sso::Nonce.issue(active_store, return_path: "/rooms/general", now:)

    assert_raises Sso::Nonce::Invalid do
      Sso::Nonce.consume!(active_store:, used_store:, nonce:, now: now + 31.minutes)
    end
  end

  test "nonce from another session raises invalid" do
    active_store = {}
    other_session_store = {}
    used_store = {}
    nonce = Sso::Nonce.issue(active_store, return_path: "/rooms/general")

    assert_raises Sso::Nonce::Invalid do
      Sso::Nonce.consume!(active_store: other_session_store, used_store:, nonce:)
    end
  end
end

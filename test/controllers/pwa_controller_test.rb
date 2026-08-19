require "test_helper"

# The offline state and its service-worker fallback are two of the "states" the
# redesign leans on. These lock in that both stay served and wired to each other.
# They deliberately stop at the Rails layer — a real offline navigation is
# service-worker behavior only a browser runs, so it isn't asserted here.
class PwaControllerTest < ActionDispatch::IntegrationTest
  test "the service worker is served without authentication and falls back to the offline shell for navigations" do
    get "/service-worker", headers: { "Accept" => "text/javascript" }

    assert_response :success
    assert_match %r{javascript}, response.media_type
    assert_match "/offline.html", response.body               # precached + fallback target
    assert_match "caches.match(OFFLINE_URL)", response.body    # document-navigation fallback
  end

  test "the web manifest is served without authentication" do
    get "/webmanifest", as: :json

    assert_response :success
  end

  test "the offline shell is served and self-contained" do
    get "/offline.html"

    assert_response :success
    assert_match "You're offline", response.body
    assert_no_match %r{https?://}, response.body   # no external assets to fetch while offline
  end
end

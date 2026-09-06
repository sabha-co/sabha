require "test_helper"

class Searches::RecentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in :kevin }

  test "renders only the signed-in user's global history, newest first, capped at eight" do
    ten = 10.times.map do |n|
      users(:kevin).searches.create!(query: "kevin #{n}", updated_at: n.minutes.from_now)
    end
    users(:jason).searches.create!(query: "jason only")
    users(:kevin).searches.create!(query: "creator scoped", creator: users(:kevin))

    get searches_recents_url

    assert_response :success
    assert_select "turbo-frame#search_palette_recents"
    assert_select ".search-palette__chip", count: 8
    assert_select ".search-palette__chip", text: ten.last.query
    assert_select ".search-palette__chip", text: ten.first.query, count: 0
    assert_no_match "jason only", response.body
    assert_no_match "creator scoped", response.body
  end

  test "renders an empty frame when there is no history" do
    get searches_recents_url

    assert_response :success
    assert_select "turbo-frame#search_palette_recents"
    assert_select ".search-palette__chip", count: 0
  end

  test "renders without the application layout" do
    get searches_recents_url

    assert_response :success
    assert_no_match "<body", response.body
  end

  test "requires authentication" do
    reset!
    get searches_recents_url

    assert_redirected_to new_session_url
  end

  test "reads the searches table once" do
    3.times { |n| users(:kevin).searches.create!(query: "q#{n}") }

    assert_equal 1, searches_queries { get searches_recents_url }
  end

  private
    def searches_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if payload[:cached] || payload[:name] == "SCHEMA"
        count += 1 if payload[:sql].include?("searches")
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
end

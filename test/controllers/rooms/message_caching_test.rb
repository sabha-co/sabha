require "test_helper"

class Rooms::MessageCachingTest < ActionDispatch::IntegrationTest
  setup do
    @perform_caching, ActionController::Base.perform_caching = ActionController::Base.perform_caching, true
    # The test environment hands Action View the cache store's config symbol rather than the store.
    @collection_cache, ActionView::PartialRenderer.collection_cache = ActionView::PartialRenderer.collection_cache, ActionController::Base.cache_store
    ActionController::Base.cache_store.clear
    sign_in :david
    @room = rooms(:watercooler)
  end

  teardown do
    ActionController::Base.perform_caching = @perform_caching
    ActionView::PartialRenderer.collection_cache = @collection_cache
  end

  test "a fully cached page loads no message presentation" do
    get room_url(@room)

    presentation_queries = capture_sql { get room_url(@room) }.grep(/action_text_rich_texts|"boosts"/)

    assert_response :success
    assert_empty presentation_queries
  end

  test "an uncached page loads message presentation in one batch" do
    rich_text_queries = capture_sql { get room_url(@room) }.grep(/action_text_rich_texts/)

    assert_response :success
    assert_equal 1, rich_text_queries.size
  end

  test "an edited message re-renders while the rest of the page comes from the cache" do
    get room_url(@room)
    message = @room.messages.ordered.last
    message.update!(body: "Rewritten after caching")

    get room_url(@room)

    assert_select "##{dom_id(message)}", text: /Rewritten after caching/
    assert_select ".message", count: @room.messages.count
  end

  test "paging back renders the earlier page through the cache" do
    anchor = @room.messages.ordered.last

    get room_messages_url(@room, before: anchor.id)
    get room_messages_url(@room, before: anchor.id)

    assert_response :success
    assert_select "##{dom_id(@room.messages.ordered.first)}"
  end

  private
    # Includes queries the query cache answers, which persists across requests within a test.
    def capture_sql(&)
      queries = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { queries << payload[:sql] }, "sql.active_record", &)
      queries
    end
end

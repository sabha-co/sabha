module SearchesHelper
  def search_results_tag(dom_id, paginator_url, highlight_mentions: true, date_separator: true, thread_messages: true, &)
    tag.div id: dom_id, class: "messages searches__results", data: {
      controller: "search-results",
      search_results_target: "messages",
      search_results_first_of_day_class: date_separator ? "message--first-of-day" : "",
      search_results_me_class: "message--me",
      search_results_threaded_class: "message--threaded",
      search_results_mentioned_class: highlight_mentions ? "message--mentioned" : "",
      search_results_formatted_class: "message--formatted",
      search_results_loading_up_class: "message--loading-up",
      search_results_loading_down_class: "message--loading-down",
      search_results_page_url_value: paginator_url,
      search_results_thread_messages_value: thread_messages
    }, &
  end

  # The palette renders in the layout, outside SearchesController, so it can't
  # lean on @recent_searches — it queries the model directly.
  def palette_recent_searches
    @palette_recent_searches ||= Current.user.searches.global.ordered.limit(8)
  end
end

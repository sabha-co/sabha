class Searches::RecentsController < ApplicationController
  # Only ever fetched into the palette's frame, so it skips the layout.
  layout false

  # The palette renders in the layout on every page, so its recent-search list
  # loads through a lazy frame instead of querying on every room visit.
  def index
    @recent_searches = Current.user.searches.global.ordered.limit(8).to_a
  end
end

class Channels::BrowseController < ApplicationController
  def index
    channels = Channel.browsable_by(Current.user).ordered
    set_page_and_extract_portion_from channels, per_page: 20
    @channels = @page.records
  end
end

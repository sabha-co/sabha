class Rooms::BrowseController < ApplicationController
  def index
    rooms = Rooms::Open.browsable_by(Current.user)
    set_page_and_extract_portion_from rooms, per_page: 20
    @rooms = @page.records
  end
end

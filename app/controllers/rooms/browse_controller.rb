class Rooms::BrowseController < ApplicationController
  def index
    rooms = Room.browsable_by(Current.user).ordered
    set_page_and_extract_portion_from rooms, per_page: 20
    @rooms = @page.records
  end
end

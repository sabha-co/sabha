class Rooms::BrowseController < ApplicationController
  def index
    rooms = Room.visible_in_browse_by(Current.user).ordered
    set_page_and_extract_portion_from rooms, per_page: 20
    @rooms = @page.records
    @joined_room_ids = Current.user.memberships.visible.pluck(:room_id).to_set
  end
end

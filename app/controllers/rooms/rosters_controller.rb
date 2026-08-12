# The contextual room panel: a presence roster (here now / away) that opens in
# the thread-panel frame from the room header's member count. Settings still
# live one click deeper, behind the panel's own link.
class Rooms::RostersController < ApplicationController
  include RoomScoped

  def show
    @roster = Room::Roster.new(@room)
  end
end

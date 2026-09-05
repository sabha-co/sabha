# Room info keeps contextual controls light. Members and management live in Settings.
class Rooms::RostersController < ApplicationController
  include RoomScoped

  def show; end
end

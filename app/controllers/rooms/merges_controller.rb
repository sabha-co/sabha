class Rooms::MergesController < ApplicationController
  before_action :ensure_is_administrator
  before_action :set_source_room
  before_action :set_target_room

  def create
    @source_room.merge_into!(@target_room)
    for_each_sidebar_section do |list_name|
      broadcast_remove_to :rooms, target: [ @source_room, helpers.dom_prefix(list_name, :list_node) ]
    end

    redirect_to room_url(@target_room), notice: "✓"
  end

  private
    def set_source_room
      @source_room = Room.opens.find(params[:room_id])
    end

    def set_target_room
      @target_room = Room.opens.active.find_by(id: params[:target_room_id])

      redirect_to edit_room_path(@source_room), alert: "Please select a destination room!" unless @target_room
    end

    def ensure_is_administrator
      head :forbidden unless Current.user.administrator?
    end
end

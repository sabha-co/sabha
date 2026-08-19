class Accounts::Bots::RoomPermissionsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_bot
  before_action :set_room, except: :index

  def index
    @bot_memberships = @bot.room_memberships.includes(:room).order("rooms.sortable_name")
    @available_rooms = @bot.rooms_available_to_add
  end

  def show
    @membership = @bot.memberships.visible.find_by(room: @room)
  end

  def create
    @room.add_member!(@bot, actor: Current.user)
    redirect_to account_bot_room_permission_path(@bot, @room)
  end

  def update
    @bot.memberships.find_by!(room: @room).update!(involvement: params[:involvement])
    redirect_to account_bot_room_permission_path(@bot, @room)
  end

  def destroy
    @room.remove_member!(@bot, actor: Current.user)
    redirect_to account_bot_room_permission_path(@bot, @room)
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:bot_id])
    end

    def set_room
      @room = Room.active.without_directs.without_threads.find(params[:room_id])
    end
end

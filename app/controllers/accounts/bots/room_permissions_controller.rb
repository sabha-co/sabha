class Accounts::Bots::RoomPermissionsController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_bot
  before_action :set_room

  def show
    @membership = @bot.memberships.visible.find_by(room: @room)
  end

  def update
    membership = @bot.memberships.visible.find_by(room: @room)

    if membership
      membership.update!(involvement: params[:involvement])
    else
      @room.add_member!(@bot, actor: Current.user)
      @bot.memberships.find_by!(room: @room).update!(involvement: params[:involvement] || :mentions)
    end

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

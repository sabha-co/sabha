class Accounts::Bots::RoomPermissionsController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_bot
  before_action :set_membership, only: %i[ update destroy ]

  def index
    @rooms = Room.active.without_directs.without_threads.ordered
    @bot_memberships = @bot.memberships.visible.index_by(&:room_id)
  end

  def create
    room = Room.without_directs.without_threads.find(params[:room_id])
    room.add_member!(@bot, actor: Current.user)
    redirect_to account_bot_room_permissions_path(@bot)
  end

  def update
    @membership.update!(involvement: params[:involvement])
    redirect_to account_bot_room_permissions_path(@bot)
  end

  def destroy
    @membership.room.remove_member!(@bot, actor: Current.user)
    redirect_to account_bot_room_permissions_path(@bot)
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:bot_id])
    end

    def set_membership
      @membership = @bot.memberships.find(params[:id])
    end
end

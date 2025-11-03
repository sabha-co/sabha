class BlocksController < ApplicationController
  before_action :set_user
  before_action :set_room

  def create
    Current.user.block!(@user)

    redirect_to room_path(@room)
  end

  def destroy
    Current.user.unblock!(@user)

    redirect_to room_path(@room)
  end

  private

  def set_user
    @user = User.find(params[:user_id])

    raise ActiveRecord::RecordNotFound if @user == Current.user
  end

  def set_room
    @room = Rooms::Direct.find_or_create_for(User.where(id: [ @user.id, Current.user.id ]))
  end
end

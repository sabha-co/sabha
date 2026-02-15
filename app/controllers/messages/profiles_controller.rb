class Messages::ProfilesController < ApplicationController
  before_action :set_user

  def show
    @activity_statuses = Membership.activity_statuses_for([ @user.id ])
  end

  private
    def set_user
      @user = User.find(params[:id])
    end
end

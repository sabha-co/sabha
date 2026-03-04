class BlocksController < ApplicationController
  before_action :set_user

  def create
    Current.user.block!(@user)
    redirect_to return_to_path
  end

  def destroy
    Current.user.unblock!(@user)
    redirect_to return_to_path
  end

  private

  def set_user
    @user = User.find(params[:user_id])

    raise ActiveRecord::RecordNotFound if @user == Current.user
  end

  def return_to_path
    if params[:return_to].present? && safe_return_path?(params[:return_to])
      params[:return_to]
    else
      root_path
    end
  end

  def safe_return_path?(path)
    uri = URI.parse(path)
    uri.relative? && uri.host.nil? && path.start_with?("/")
  rescue URI::InvalidURIError
    false
  end
end

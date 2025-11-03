class Users::SearchesController < ApplicationController
  before_action :set_user

  def create
    Current.user.searches.record(query, creator: @user)
    redirect_to user_messages_url(@user, q: query)
  end

  def clear
    Current.user.searches.for_creator(@user).destroy_all
    redirect_to user_messages_url(@user)
  end

  private
    def set_user
      @user = User.find(params[:user_id])
    end

    def query
      params[:q]&.gsub(/[^[:word:]]/, " ")
    end
end

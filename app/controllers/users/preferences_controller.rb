class Users::PreferencesController < ApplicationController
  def update
    Current.user.save_preference(params[:preference], params[:value])

    redirect_to user_sidebar_path
  end
end

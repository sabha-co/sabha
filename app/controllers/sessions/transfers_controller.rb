class Sessions::TransfersController < ApplicationController
  allow_unauthenticated_access

  def show
  end

  def update
    if user = User.active.find_by_transfer_id(params[:id])
      start_new_session_for user
      redirect_to post_authenticating_url
    else
      redirect_to new_session_url, alert: "That sign-in link is invalid or has expired."
    end
  end
end

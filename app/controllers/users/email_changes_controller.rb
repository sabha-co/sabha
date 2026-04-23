class Users::EmailChangesController < ApplicationController
  def destroy
    if Current.user.cancel_email_change!
      redirect_to user_profile_url, notice: "Email change cancelled."
    else
      redirect_to user_profile_url
    end
  end
end

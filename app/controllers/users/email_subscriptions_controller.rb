class Users::EmailSubscriptionsController < ApplicationController
  def show ; end

  def update
    Current.user.toggle_email_subscription

    redirect_to email_subscription_url
  end
end

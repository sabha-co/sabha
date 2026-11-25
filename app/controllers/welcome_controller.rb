class WelcomeController < ApplicationController
  def show
    if Current.user.channels.any?
      channel = landing_channel
      target = channel_url(channel)
      target = target + "?" + request.query_string if request.query_string.present?
      redirect_to target
    else
      render
    end
  end
end

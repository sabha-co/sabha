class Channels::AccessController < ApplicationController
  include ChannelScoped

  before_action :ensure_can_administer
  before_action :ensure_channel_is_convertible

  def update
    channel = @channel.toggle_access!(open: open_access?)
    ChannelUpdateBroadcastJob.perform_later(channel)

    notice = open_access? ? "Channel is now public" : "Channel is now private"
    redirect_to helpers.edit_channel_path(channel), notice: notice
  end

  private
    def open_access?
      params[:open] == "1"
    end

    # Only open and closed channels carry this toggle, and the members panel only
    # draws it for them. Anything else arriving here — a direct channel, a forum, a
    # thread — is an attempt to republish it, not a switch someone was shown.
    def ensure_channel_is_convertible
      head :forbidden unless @channel.convertible?
    end
end

module TrackedChannelVisit
  extend ActiveSupport::Concern

  included do
    helper_method :last_channel_visited
    helper_method :landing_channel
  end

  def remember_last_channel_visited
    cookies.permanent[:last_channel] = @channel.id
  end

  def landing_channel
    original_open_channel = Channel.opens.active.order(:created_at).first
    if original_open_channel && Current.user.member_of?(original_open_channel)
      original_open_channel
    else
      last_channel_visited
    end
  end

  def last_channel_visited
    Current.user.channels.find_by(id: cookies[:last_channel]) || default_channel
  end

  private
    def default_channel
      Current.user.channels.original
    end
end

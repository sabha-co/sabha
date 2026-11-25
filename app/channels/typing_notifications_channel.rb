class TypingNotificationsChannel < ChannelScopedChannel
  def subscribed
    if channel
      stream_for channel, whisper: true
    else
      reject
    end
  end

  def start(data)
    with_tenant_context do
      broadcast_to channel, action: :start, user: current_user_attributes if channel
    end
  end

  def stop(data)
    with_tenant_context do
      broadcast_to channel, action: :stop, user: current_user_attributes if channel
    end
  end

  private
    def current_user_attributes
      current_user.slice(:id, :name)
    end
end

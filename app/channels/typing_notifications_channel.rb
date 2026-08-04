class TypingNotificationsChannel < RoomChannel
  def subscribed
    if room
      stream_for room, whisper: true
    else
      reject
    end
  end

  def start(data)
    with_tenant_context do
      broadcast_to room, action: :start, user: current_user_attributes if room
    end
  end

  def stop(data)
    with_tenant_context do
      broadcast_to room, action: :stop, user: current_user_attributes if room
    end
  end

  private
    def current_user_attributes
      current_user.slice(:id, :name)
    end
end

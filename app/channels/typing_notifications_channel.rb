class TypingNotificationsChannel < RoomChannel
  def subscribed
    if @room = find_room
      stream_for @room, **stream_options
    else
      reject
    end
  end

  def start(data)
    broadcast_to room, action: :start, user: current_user_attributes if room
  end

  def stop(data)
    broadcast_to room, action: :stop, user: current_user_attributes if room
  end

  private
    def current_user_attributes
      current_user.slice(:id, :name)
    end

    def stream_options
      AnyCable::Rails.enabled? ? { whisper: true } : {}
    end
end

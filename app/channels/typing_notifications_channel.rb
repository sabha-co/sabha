class TypingNotificationsChannel < RoomChannel
  def start(data)
    broadcast_to @room, action: :start, user: current_user_attributes
  end

  def stop(data)
    broadcast_to @room, action: :stop, user: current_user_attributes
  end

  private
    def current_user_attributes
      current_user.slice(:id, :name)
    end
end

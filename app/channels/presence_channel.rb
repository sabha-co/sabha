class PresenceChannel < RoomChannel
  on_subscribe   :present, unless: :subscription_rejected?
  on_unsubscribe :absent,  unless: :subscription_rejected?

  def present
    m = membership
    return unless m

    m.present
    ActionCable.server.broadcast "user_#{current_user.id}_reads", { room_id: m.room_id }
  end

  def absent
    membership&.disconnected
  end

  def refresh
    membership&.refresh_connection
  end

  private
    def membership
      room&.memberships&.find_by(user: current_user)
    end
end

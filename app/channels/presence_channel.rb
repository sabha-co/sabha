class PresenceChannel < RoomChannel
  on_subscribe   :present, unless: :subscription_rejected?
  on_unsubscribe :absent,  unless: :subscription_rejected?

  def present
    with_tenant_context do
      m = membership
      return unless m

      m.present
      ReadRoomsChannel.broadcast_to(current_user, { room_id: m.room_id })
    end
  end

  def absent
    with_tenant_context do
      membership&.disconnected
    end
  end

  def refresh
    with_tenant_context do
      membership&.refresh_connection
    end
  end

  private
    def membership
      with_tenant_context do
        room&.memberships&.find_by(user: current_user)
      end
    end
end

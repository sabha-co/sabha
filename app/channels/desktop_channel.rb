class DesktopChannel < ApplicationCable::Channel
  def subscribed
    with_tenant_context do
      return reject unless current_user

      stream_for current_user
      transmit self.class.badge_for(current_user)
    end
  end

  # Tenant-scoped in SaaS through the user's GlobalID, like every other
  # per-user channel.
  def self.broadcast_to_user(user, payload)
    broadcast_to(user, payload) if Desktop.notifications_enabled?
  end

  def self.broadcast_badge_to(user)
    broadcast_to_user(user, badge_for(user))
  end

  def self.badge_for(user)
    { type: "badge", protocol_major: Sabha::PROTOCOL_MAJOR, count: user.badge_count }
  end
end

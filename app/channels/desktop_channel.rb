class DesktopChannel < ApplicationCable::Channel
  def subscribed
    with_tenant_context do
      unless current_user
        reject
        return
      end

      stream_from stream_name_for(current_user)
      transmit self.class.badge_for(current_user)
    end
  end

  def self.stream_name_for(user)
    if Sabha.saas?
      tenant = ApplicationRecord.current_tenant
      raise "DesktopChannel.stream_name_for requires tenant context in SaaS mode" if tenant.blank?

      "desktop:#{tenant}:#{user.id}"
    else
      "desktop:#{user.id}"
    end
  end

  def self.broadcast_to_user(user, payload)
    return unless Desktop.notifications_enabled?

    ActionCable.server.broadcast(stream_name_for(user), payload)
  end

  def self.broadcast_badge_to(user)
    broadcast_to_user(user, badge_for(user))
  end

  def self.badge_for(user)
    { type: "badge", protocol_major: Sabha::PROTOCOL_MAJOR, count: user.badge_count }
  end

  private
    def stream_name_for(user)
      self.class.stream_name_for(user)
    end
end

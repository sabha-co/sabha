class DesktopChannel < ApplicationCable::Channel
  def subscribed
    with_tenant_context do
      unless current_user
        reject
        return
      end

      stream_from stream_name_for(current_user)
      transmit Desktop::BadgeState.snapshot_for(current_user)
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
    return unless Desktop::BadgeState.enabled?

    ActionCable.server.broadcast(stream_name_for(user), payload)
  end

  private
    def stream_name_for(user)
      self.class.stream_name_for(user)
    end
end

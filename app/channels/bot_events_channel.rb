class BotEventsChannel < ApplicationCable::Channel
  def subscribed
    with_tenant_context do
      unless current_user&.bot?
        reject
        return
      end

      stream_from self.class.stream_name_for(current_user)
    end
  end

  # Stream name is tenant-scoped in SaaS mode so bot IDs (which are NOT unique
  # across tenants) cannot collide. Reads from `ApplicationRecord.current_tenant`
  # rather than taking it as an argument so callers can't accidentally produce
  # an unscoped stream by forgetting to pass it.
  def self.stream_name_for(bot)
    if Sabha.saas?
      tenant = ApplicationRecord.current_tenant
      raise "BotEventsChannel.stream_name_for requires tenant context in SaaS mode" if tenant.blank?
      "bot_events:#{tenant}:#{bot.id}"
    else
      "bot_events:#{bot.id}"
    end
  end
end

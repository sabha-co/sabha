class BotEventsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.bot?
      reject
      return
    end

    stream_from self.class.stream_name_for(current_user, tenant: connection.try(:current_tenant))
  end

  def self.stream_name_for(bot, tenant: nil)
    tenant ? "bot_events:#{tenant}:#{bot.id}" : "bot_events:#{bot.id}"
  end
end

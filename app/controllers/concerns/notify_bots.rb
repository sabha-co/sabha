module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    base_url = request.base_url + request.script_name
    room = item.try(:room) || item.try(:message)&.room

    if room
      room.bot_memberships_for_events(item, event).each do |membership|
        bot = membership.user

        broadcast_to_bot_channel(bot, item, event, base_url: base_url)

        if bot.webhook_url.present?
          reply = membership.receives_mentions? && event == :created
          bot.deliver_webhook_later(item, event, reply: reply, base_url: base_url)
        end
      end
    else
      User.active_bots.each do |bot|
        broadcast_to_bot_channel(bot, item, event, base_url: base_url)
        bot.deliver_webhook_later(item, event, base_url: base_url) if bot.webhook_url.present?
      end
    end
  end

  private

  def broadcast_to_bot_channel(bot, item, event, base_url:)
    payload = Webhook.build_event_payload(item, event, bot: bot, base_url: base_url)
    tenant = Sabha.saas? ? ApplicationRecord.current_tenant : nil
    stream = BotEventsChannel.stream_name_for(bot, tenant: tenant)
    ActionCable.server.broadcast(stream, JSON.parse(payload))
  end
end

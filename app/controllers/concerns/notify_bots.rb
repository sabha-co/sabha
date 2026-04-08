module NotifyBots
  extend ActiveSupport::Concern

  def notify_bots(item, event)
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
      User.active_bots.includes(:webhook).each do |bot|
        broadcast_to_bot_channel(bot, item, event, base_url: base_url)
        bot.deliver_webhook_later(item, event, base_url: base_url) if bot.webhook_url.present?
      end
    end
  end

  private

  def broadcast_to_bot_channel(bot, item, event, base_url:)
    payload = Bot::EventPayload.build(item, event, bot: bot, base_url: base_url)
    stream = BotEventsChannel.stream_name_for(bot, tenant: ApplicationRecord.try(:current_tenant))
    ActionCable.server.broadcast(stream, payload)
  end
end

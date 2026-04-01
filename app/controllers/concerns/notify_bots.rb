module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    base_url = request.base_url + request.script_name
    room = item.try(:room) || item.try(:message)&.room

    if room
      room.bot_memberships_for_webhook(item, event).each do |membership|
        reply = membership.receives_mentions? && event == :created
        membership.user.deliver_webhook_later(item, event, reply: reply, base_url: base_url)
      end
    else
      User.active_bots.joins(:webhook).each do |bot|
        bot.deliver_webhook_later(item, event, base_url: base_url)
      end
    end
  end
end

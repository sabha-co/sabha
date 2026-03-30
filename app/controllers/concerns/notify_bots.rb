module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    if (room = item.try(:room))
      room.bot_memberships_for_webhook(item, event).each do |membership|
        reply = membership.involved_in_mentions? && event == :created
        membership.user.deliver_webhook_later(item, event, reply: reply)
      end
    else
      User.active_bots.joins(:webhook).each do |bot|
        bot.deliver_webhook_later(item, event)
      end
    end
  end
end

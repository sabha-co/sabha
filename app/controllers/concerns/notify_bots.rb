module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    room = item.try(:room)
    return unless room

    room.bot_memberships_for_webhook(item, event).each do |membership|
      reply = membership.involved_in_mentions? && event == :created
      membership.user.deliver_webhook_later(item, event, reply: reply)
    end
  end
end

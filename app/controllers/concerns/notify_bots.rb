module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    bots_eligible_for_webhook(item, event).each { |bot| bot.deliver_webhooks_later(item, event) }
  end

  def bots_eligible_for_webhook(item, event)
    bots_receiving_everything = User.active_bots.observing_everything

    if (message = item).is_a?(Message) && event == :created
      mentioned_bots = message.room.direct? ? message.room.users.active_bots : message.mentionees.active_bots
      (mentioned_bots + bots_receiving_everything).uniq
    else
      bots_receiving_everything
    end
  end
end

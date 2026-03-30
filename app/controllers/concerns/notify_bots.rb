module NotifyBots
  extend ActiveSupport::Concern

  def deliver_webhooks_to_bots(item, event)
    room = item.try(:room)
    return unless room

    bot_memberships_for_webhook(item, event, room).each do |membership|
      reply = membership.involved_in_mentions? && event == :created
      membership.user.deliver_webhook_later(item, event, reply: reply)
    end
  end

  private
    def bot_memberships_for_webhook(item, event, room)
      bot_ids_with_webhook = User.active_bots.joins(:webhook).pluck(:id)
      return Membership.none if bot_ids_with_webhook.empty?

      memberships = room.memberships.active
        .where.not(involvement: [ :invisible, :nothing ])
        .where(user_id: bot_ids_with_webhook)
        .includes(user: :webhook)

      if room.direct?
        memberships.to_a
      elsif item.is_a?(Message) && event == :created
        memberships.to_a.select do |m|
          m.involved_in_everything? || mentioned?(item, m.user)
        end
      else
        memberships.where(involvement: :everything).to_a
      end
    end

    def mentioned?(message, bot)
      message.mentionees.include?(bot) || message.mentions_everyone?
    end
end

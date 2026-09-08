# Fans an outbound bot event out to its recipients. Callers decide when an event
# happens and supply the URL context; this class owns who hears about it and how
# it reaches them. Selection stays on `Room`, payload construction on
# `Bot::EventPayload`, and HTTP delivery on `Webhook`.
class Bot::Event
  def initialize(item, event, base_url:)
    @item, @event, @base_url = item, event, base_url
  end

  def dispatch
    if room
      room.bot_memberships_for_events(item, event).each do |membership|
        deliver_to membership.user, reply: accepts_reply?(membership)
      end
    else
      User.active_bots.includes(:webhook).each { |bot| deliver_to bot }
    end
  end

  private
    attr_reader :item, :event, :base_url

    # Account-level events like user changes belong to no room, and reach every
    # active bot instead.
    def room
      @room ||= item.try(:room) || item.try(:message)&.room
    end

    # :mentions and :everything memberships both accept a reply, and every
    # :created event qualifies — a new boost as much as a new message. Whether
    # the bot hears about the event at all is settled upstream by
    # `bot_memberships_for_events`.
    def accepts_reply?(membership)
      membership.receives_mentions? && event == :created
    end

    def deliver_to(bot, reply: false)
      ActionCable.server.broadcast BotEventsChannel.stream_name_for(bot),
        Bot::EventPayload.build(item, event, bot: bot, base_url: base_url)

      bot.deliver_webhook_later item, event, reply: reply, base_url: base_url if bot.webhook_url.present?
    end
end

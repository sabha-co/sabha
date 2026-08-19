module BotsHelper
  # The list row's scope line: "Posts to #a, #b · key rotated N ago", or the
  # no-rooms warning. The key age is omitted for bots that predate the digest
  # cutover (no rotation timestamp on file).
  def bot_rooms_summary(bot, limit: 2)
    rooms = bot.room_memberships.map(&:room)

    scope = if rooms.empty?
      "No rooms yet — it can't post until you add one"
    else
      shown = rooms.first(limit).map { |room| "##{room.name}" }
      remainder = rooms.size - shown.size
      shown << "#{remainder} more" if remainder.positive?
      "Posts to #{shown.join(", ")}"
    end

    [ scope, bot_key_age(bot) ].compact.join(" · ")
  end

  def bot_key_age(bot)
    "key rotated #{time_ago_in_words(bot.bot_key_rotated_at)} ago" if bot.bot_key_rotated_at
  end

  def bot_webhook_summary(bot)
    bot.webhook_url.presence || "No webhook — outbound only"
  end
end

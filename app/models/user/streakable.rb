module User::Streakable
  extend ActiveSupport::Concern

  def current_streak
    if streak_updated_on.nil?
      super
    elsif streak_updated_on < Date.yesterday
      0
    else
      super
    end
  end

  def recalculate_streak!(excluding_message: nil)
    return if posted_on?(Date.current, excluding: excluding_message)

    new_streak = posted_on?(Date.yesterday) ? current_streak + 1 : 1
    update_columns(current_streak: new_streak, streak_updated_on: Date.current)
  end

  def posted_on?(date, excluding: nil)
    scope = messages.joins(:channel)
                    .joins("LEFT JOIN messages AS parent_messages ON channels.parent_message_id = parent_messages.id")
                    .joins("LEFT JOIN channels AS parent_channels ON parent_messages.channel_id = parent_channels.id")
                    .where.not(channels: { type: "Channels::Direct" })
                    .where("parent_channels.type IS NULL OR parent_channels.type != ?", "Channels::Direct")
                    .where("DATE(messages.created_at) = ?", date)
                    .user_authored
    scope = scope.where.not(id: excluding.id) if excluding
    scope.exists?
  end
end

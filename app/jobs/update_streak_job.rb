class UpdateStreakJob < ApplicationJob
  def perform(user_id:, excluding_message_id:)
    user = User.find_by(id: user_id)
    return unless user

    excluding_message = Message.find_by(id: excluding_message_id)
    user.recalculate_streak!(excluding_message: excluding_message)
  end
end

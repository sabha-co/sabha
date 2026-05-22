module Message::Streakable
  extend ActiveSupport::Concern

  included do
    after_create_commit :update_creator_streak
  end

  private
    def update_creator_streak
      return if room.direct? || room.parent_room&.direct? || welcome?
      UpdateStreakJob.perform_later(user_id: creator_id, excluding_message_id: id)
    end
end

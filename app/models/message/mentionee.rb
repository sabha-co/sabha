module Message::Mentionee
  extend ActiveSupport::Concern

  included do
    before_save :set_mentions_everyone_flag
    after_save :reset_mentionee_memo

    scope :mentioning, ->(user_id) {
      where(
        "EXISTS (SELECT 1 FROM notifications WHERE notifications.message_id = messages.id
          AND notifications.user_id = ? AND notifications.activity_type = 'mention')
         OR messages.mentions_everyone = ?",
        user_id, true
      )
    }
  end

  def mentionees
    @mentionees ||=
      if mentions_everyone?
        room.users.to_a
      elsif (ids = mentioned_users.map(&:id)).any?
        room.users.where(id: ids).to_a
      else
        []
      end
  end

  def mentionee_ids
    @mentionee_ids ||= mentionees.map(&:id)
  end

  private
    def reset_mentionee_memo
      @mentionees = @mentionee_ids = nil
    end

    def set_mentions_everyone_flag
      self.mentions_everyone = mentions_everyone_in_body?
    end

    def mentions_everyone_in_body?
      return false unless body.body
      body.body.attachables.any? { |a| a.is_a?(Everyone) }
    end

    def mentioned_users
      if body.body
        (body.body.attachables.grep(User) + cited_users).uniq
      else
        []
      end
    end

    def cited_users
      cited_message_ids = body.body.fragment.find_all("cite a").map { |a| a["href"].to_s[/@([^@]+)$/, 1] }
      return User.none if cited_message_ids.empty?
      User.joins(:messages).where.not(id: self.creator_id).where(messages: { id: cited_message_ids }).distinct
    end
end

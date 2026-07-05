module Message::Mentionee
  extend ActiveSupport::Concern

  included do
    before_save :set_mentions_everyone_flag
    after_save :reset_mentionee_memo
    after_create_commit :create_mention_notifications
    after_update_commit :destroy_stale_mention_notifications

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
        room.mentionable_users.to_a
      elsif (ids = mentioned_users.map(&:id)).any?
        room.mentionable_users.where(id: ids).to_a
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

    def create_mention_notifications
      return if event?
      return if room.direct? || room.parent_room&.direct?

      recipient_ids = if mentions_everyone?
        room.user_ids - [ creator_id ]
      else
        mentionee_ids - [ creator_id ]
      end

      return if recipient_ids.empty?

      now = Time.current
      Notification.insert_all(
        recipient_ids.map { |uid|
          { user_id: uid, message_id: id, actor_id: creator_id, activity_type: "mention", created_at: now, updated_at: now }
        },
        unique_by: "index_notifications_on_message_user_type"
      )

      User.where(id: recipient_ids).each(&:broadcast_activity_indicator)
      broadcast_mention_notifications
    end

    def destroy_stale_mention_notifications
      return if room.direct?
      return unless active? # already handled by Message::Unreadable#destroy_notifications_if_deactivated
      return unless rich_text_body.saved_changes?

      current_recipient_ids = if mentions_everyone_in_body?
        room.user_ids - [ creator_id ]
      else
        mentioned_users.map(&:id) - [ creator_id ]
      end

      Notification.delete_all_and_broadcast(
        Notification.where(message_id: id, activity_type: "mention")
                    .where.not(user_id: current_recipient_ids)
      )
    end
end

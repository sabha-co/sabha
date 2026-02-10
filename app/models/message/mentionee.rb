module Message::Mentionee
  extend ActiveSupport::Concern

  included do
    has_many :mentions, dependent: :delete_all
    has_many :mentioned_users_association, through: :mentions, source: :user

    after_save :create_mentionees

    scope :mentioning, ->(user_id) {
      left_joins(:mentions)
        .where("mentions.user_id = ? OR messages.mentions_everyone = ?", user_id, true)
        .distinct
    }
    scope :without_user_mentions, ->(user) {
      left_outer_joins(:mentions)
        .where.not(mentions: { user_id: user.id })
        .where(mentions_everyone: false)
        .distinct
    }
  end

  def mentionees
    if mentions_everyone?
      room.users
    elsif persisted?
      mentioned_users_association
    else
      # For unsaved messages, parse the body directly and filter to room members only
      mentioned_users.select { |user| room.user_ids.include?(user.id) }
    end
  end

  def mentionee_ids
    if mentions_everyone?
      room.user_ids
    else
      mentions.pluck(:user_id)
    end
  end

  private
    def create_mentionees
      if mentions_everyone_in_body?
        update_column(:mentions_everyone, true)
      else
        sync_mentions_with(mentioned_users)
      end
    end

    def sync_mentions_with(users)
      return if users.empty?

      existing_user_ids = mentions.pluck(:user_id).to_set
      new_users = users.reject { |user| existing_user_ids.include?(user.id) }

      return if new_users.empty?

      Mention.insert_all(
        new_users.map { |user| { message_id: id, user_id: user.id } }
      )
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
      User.joins(:messages).where.not(id: self.creator_id).where(messages: { id: cited_message_ids }).distinct
    end
end

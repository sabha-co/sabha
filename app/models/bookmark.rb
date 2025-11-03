class Bookmark < ApplicationRecord
  include Pagination, Deactivatable

  belongs_to :user
  belongs_to :message

  scope :ordered, -> { order(:created_at) }

  def self.populate_for(messages)
    return messages if messages.empty?

    message_ids = messages.pluck(:id) if messages.is_a?(ActiveRecord::Relation)
    message_ids ||= messages.map(&:id)

    bookmarked_ids = Bookmark.active
                             .where(user_id: Current.user.id, message_id: message_ids)
                             .pluck(:message_id)
                             .to_set

    messages.each { |message| message.bookmarked = bookmarked_ids.include?(message.id) }
  end
end

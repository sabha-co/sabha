class Bookmark < ApplicationRecord
  include Pagination, Deactivatable

  belongs_to :user
  belongs_to :message

  scope :ordered, -> { order(:created_at) }

  def self.with_bookmark_status(messages, user: Current.user)
    return messages if messages.empty?

    message_ids = messages.is_a?(ActiveRecord::Relation) ? messages.pluck(:id) : messages.map(&:id)

    bookmarked_ids = active
                       .where(user: user, message_id: message_ids)
                       .pluck(:message_id)
                       .to_set

    messages.each { |message| message.bookmarked = bookmarked_ids.include?(message.id) }
  end
end

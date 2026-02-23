class Bookmark < ApplicationRecord
  include Pagination

  belongs_to :user
  belongs_to :message

  scope :ordered, -> { order(:created_at) }
end

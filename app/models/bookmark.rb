class Bookmark < ApplicationRecord
  include Pagination, Deactivatable

  belongs_to :user
  belongs_to :message

  scope :ordered, -> { order(:created_at) }
end

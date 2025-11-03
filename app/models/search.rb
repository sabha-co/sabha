class Search < ApplicationRecord
  belongs_to :user
  belongs_to :creator, class_name: "User", optional: true

  after_create :trim_recent_searches

  scope :global, -> { where(creator: nil) }
  scope :for_creator, ->(user) { where(creator: user) }
  scope :ordered, -> { order(updated_at: :desc) }

  class << self
    def record(query, creator: nil)
      find_or_create_by(query: query, creator:).touch
    end
  end

  private
    def trim_recent_searches
      user.searches.for_creator(creator).excluding(user.searches.for_creator(creator).ordered.limit(10)).destroy_all
    end
end

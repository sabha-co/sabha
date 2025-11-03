module User::Preferences
  extend ActiveSupport::Concern

  included do
    serialize :preferences, coder: JSON
    store_accessor :preferences, :all_rooms_sort_order
    validates :all_rooms_sort_order, inclusion: { in: %w[most_active last_updated alphabetical] }, allow_blank: true
  end

  def save_preference(key, value)
    self.preferences[key] = value
    save!
  end

  def preference(key)
    preferences&.[](key)
  end
end

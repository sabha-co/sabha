class SingleSignOnRecord < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :user_id, uniqueness: true
end

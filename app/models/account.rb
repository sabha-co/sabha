class Account < ApplicationRecord
  include Joinable, Deactivatable

  has_one_attached :logo
end

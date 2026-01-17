module Account::Joinable
  extend ActiveSupport::Concern

  included do
    has_many :join_codes, class_name: "Account::JoinCode", dependent: :destroy

    after_create :create_global_join_code
  end

  # Returns the global (admin) join code for backward compatibility
  def join_code
    join_codes.global.first
  end

  def reset_join_code
    join_code.regenerate_code
  end

  private
    def create_global_join_code
      join_codes.create!
    end
end

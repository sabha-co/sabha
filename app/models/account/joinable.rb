module Account::Joinable
  extend ActiveSupport::Concern

  included do
    has_many :join_codes, class_name: "Account::JoinCode", dependent: :destroy

    after_create :create_global_join_code
  end

  def join_code
    join_codes.global.first.tap do |code|
      code.regenerate_code if code&.expired?
    end
  end

  def reset_join_code
    join_code.regenerate_code
  end

  def toggle_join_code_expiration
    join_code.toggle_expiration
  end

  def active_bot_invite_code
    join_codes.bot.active.order(created_at: :desc).first
  end

  def generate_bot_invite_code!
    regenerated = join_codes.bot.active.destroy_all.any?
    code = join_codes.create!(kind: :bot)
    [ code, regenerated ]
  end

  private
    def create_global_join_code
      join_codes.create!
    end
end

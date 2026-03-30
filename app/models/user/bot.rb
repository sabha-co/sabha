module User::Bot
  extend ActiveSupport::Concern

  included do
    scope :active_bots, -> { active.where(role: :bot) }
    scope :without_bots, -> { where.not(role: :bot) }
    has_one :webhook, dependent: :destroy
  end

  module ClassMethods
    def create_bot!(attributes)
      attributes = attributes.to_h.symbolize_keys
      bot_token = generate_bot_token
      webhook_url = attributes.delete(:webhook_url) || attributes.delete(:mentions_url) || attributes.delete(:everything_url)

      User.create!(**attributes, bot_token: bot_token, role: :bot).tap do |user|
        user.create_webhook!(url: webhook_url) if webhook_url.present?
      end
    end

    def authenticate_bot(bot_key)
      bot_id, bot_token = bot_key.split("-")
      return nil if bot_token.blank?
      active_bots.find_by(id: bot_id, bot_token: bot_token)
    end

    def generate_bot_token
      SecureRandom.alphanumeric(12)
    end
  end

  def update_bot!(attributes)
    attributes = attributes.to_h.symbolize_keys
    has_webhook_param = attributes.key?(:webhook_url) || attributes.key?(:mentions_url) || attributes.key?(:everything_url)
    webhook_url = attributes.delete(:webhook_url) || attributes.delete(:mentions_url) || attributes.delete(:everything_url)

    transaction do
      update_webhook_url!(webhook_url) if has_webhook_param
      update!(attributes)
    end
  end

  def bot_key
    "#{id}-#{bot_token}"
  end

  def reset_bot_key
    update! bot_token: self.class.generate_bot_token
  end

  def webhook_url
    webhook&.url
  end

  def deliver_webhook_later(item, event, reply: false)
    webhook&.deliver_later(item, event, reply: reply)
  end

  private
    def update_webhook_url!(url)
      if url.present?
        webhook&.update!(url: url) || create_webhook!(url: url)
      else
        webhook&.destroy
      end
    end
end

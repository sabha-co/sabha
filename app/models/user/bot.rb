module User::Bot
  extend ActiveSupport::Concern

  included do
    scope :active_bots, -> { active.where(role: :bot) }
    scope :without_bots, -> { where.not(role: :bot) }
    scope :observing_everything, -> { joins(:webhooks).where(webhooks: { receives: :everything }).distinct }
    has_many :webhooks, dependent: :destroy
  end

  module ClassMethods
    def create_bot!(attributes)
      bot_token = generate_bot_token
      mentions_url = attributes.delete(:mentions_url)
      everything_url = attributes.delete(:everything_url)

      User.create!(**attributes, bot_token: bot_token, role: :bot).tap do |user|
        user.webhooks.create!(url: mentions_url, receives: :mentions) if mentions_url
        user.webhooks.create!(url: everything_url, receives: :everything) if everything_url
      end
    end

    def authenticate_bot(bot_key)
      bot_id, bot_token = bot_key.split("-")
      active.find_by(id: bot_id, bot_token: bot_token)
    end

    def generate_bot_token
      SecureRandom.alphanumeric(12)
    end
  end

  def update_bot!(attributes)
    transaction do
      update_webhook_url!(attributes.delete(:mentions_url), :mentions)
      update_webhook_url!(attributes.delete(:everything_url), :everything)
      update!(attributes)
    end
  end


  def bot_key
    "#{id}-#{bot_token}"
  end

  def reset_bot_key
    update! bot_token: self.class.generate_bot_token
  end

  def mentions_url
    mentions_webhook&.url
  end

  def everything_url
    everything_webhook&.url
  end

  def deliver_webhooks_later(item, event)
    webhooks.each do |webhook|
      webhook.deliver_later(item, event) if webhook.cares_about?(item, event)
    end
  end

  private
    def mentions_webhook
      webhooks.receiving_mentions.first
    end

    def everything_webhook
      webhooks.receiving_everything.first
    end

    def update_webhook_url!(url, receives)
      if url.present?
        webhooks.where(receives: receives).first&.update!(url: url) || webhooks.create!(url: url, receives: receives)
      else
        webhooks.where(receives: receives).destroy_all
      end
    end
end

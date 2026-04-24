require "openssl"
require "securerandom"

class User::Bot::WebhookSigner
  def self.headers_for(bot:, event_name:, raw_body:)
    new(bot).headers_for(event_name: event_name, raw_body: raw_body)
  end

  def initialize(bot)
    @bot = bot
  end

  def headers_for(event_name:, raw_body:)
    ensure_secret!

    timestamp = Time.current.to_i.to_s
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @bot.webhook_secret, "#{timestamp}.#{raw_body}")

    {
      "X-Sabha-Signature" => signature,
      "X-Sabha-Timestamp" => timestamp,
      "X-Sabha-Event"     => event_name.to_s,
      "X-Sabha-Delivery"  => SecureRandom.uuid
    }
  end

  private
    def ensure_secret!
      return if @bot.webhook_secret.present?
      @bot.update!(webhook_secret: @bot.class.generate_webhook_secret)
    end
end

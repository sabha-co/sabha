# === Resend ===

require "resend"

class ResendDeliveryMethod
  def initialize(settings)
    @settings = settings
  end

  PASSTHROUGH_HEADERS = %w[ List-Unsubscribe List-Unsubscribe-Post ].freeze

  def deliver!(mail)
    api_key = @settings[:api_key] || ENV["RESEND_API_KEY"]

    if api_key.blank?
      raise ArgumentError, "Resend API key is missing. Please set RESEND_API_KEY environment variable."
    end

    Resend.api_key = api_key.to_s.strip

    params = {
      from: mail.from.first,
      to: mail.to,
      subject: mail.subject
    }

    if mail.text_part&.body
      params[:text] = mail.text_part.body.to_s
      if mail.html_part&.body
        params[:html] = mail.html_part.body.to_s
      end
    else
      body_content = mail.body.to_s
      if mail.content_type&.include?("text/html")
        params[:html] = body_content
      else
        params[:text] = body_content
      end
    end

    # Provider-side idempotency: stable across Solid Queue retries so a
    # double-deliver hits Resend's dedup, not the recipient's inbox.
    if (idempotency_key = mail.header["X-Idempotency-Key"]&.value).present?
      params[:idempotency_key] = idempotency_key
    end

    # Forward RFC 8058 unsubscribe headers — Resend doesn't read them off the
    # raw mail object, only the explicit `headers` param.
    forwarded = PASSTHROUGH_HEADERS.each_with_object({}) do |name, memo|
      value = mail.header[name]&.value
      memo[name] = value if value.present?
    end
    params[:headers] = forwarded if forwarded.any?

    Resend::Emails.send(params)
  end
end

# === SES ===

SES_AVAILABLE = begin
  require "aws-sdk-sesv2"
  true
rescue LoadError
  false
end

class SesDeliveryMethod
  def initialize(settings)
    @settings = settings
  end

  # Internal headers consumed before send so they don't leak to recipients.
  # X-Idempotency-Key is the dispatcher's retry-dedup signal; SES has no
  # per-call idempotency parameter on send_email, so we just drop the header.
  INTERNAL_HEADERS = %w[ X-Idempotency-Key X-SES-CONFIGURATION-SET ].freeze

  def deliver!(mail)
    raise "aws-sdk-sesv2 gem is required for SES delivery. Add it to your Gemfile." unless SES_AVAILABLE

    config_set = configuration_set_for(mail)
    INTERNAL_HEADERS.each { |name| mail[name] = nil }

    params = { content: { raw: { data: mail.to_s } } }
    params[:configuration_set_name] = config_set if config_set.present?

    client.send_email(**params)
  end

  private
    def client
      @client ||= Aws::SESV2::Client.new(**client_options)
    end

    def client_options
      options = {}
      options[:region] = ENV["AWS_SES_REGION"] if ENV["AWS_SES_REGION"].present?

      access_key = ENV["AWS_SES_ACCESS_KEY_ID"]
      secret_key = ENV["AWS_SES_SECRET_ACCESS_KEY"]

      if access_key.present? && secret_key.present?
        options[:credentials] = Aws::Credentials.new(access_key, secret_key)
      end

      options
    end

    # Per-email override via X-SES-CONFIGURATION-SET header (used by Sessy for observability)
    def configuration_set_for(mail)
      mail.header["X-SES-CONFIGURATION-SET"]&.value || ENV.fetch("SES_CONFIGURATION_SET", "sabha-ses")
    end
end

# Register delivery methods lazily to avoid loading ActionMailer too early
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :ses, SesDeliveryMethod
  add_delivery_method :resend, ResendDeliveryMethod
end

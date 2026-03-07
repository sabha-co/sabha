begin
  require "aws-sdk-sesv2"
rescue LoadError
  return # gem not available in self-hosted mode
end

class SesDeliveryMethod
  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    client.send_email(
      content: { raw: { data: mail.to_s } },
      configuration_set_name: configuration_set_for(mail)
    )
  end

  private
    def client
      @client ||= Aws::SESV2::Client.new(**client_options)
    end

    def client_options
      options = {}
      options[:region] = ENV["AWS_SES_REGION"] if ENV["AWS_SES_REGION"].present?

      # SES-specific credentials; falls back to SDK default chain (env vars, IAM role, etc.)
      access_key = ENV["AWS_SES_ACCESS_KEY_ID"]
      secret_key = ENV["AWS_SES_SECRET_ACCESS_KEY"]

      if access_key.present? && secret_key.present?
        options[:credentials] = Aws::Credentials.new(access_key, secret_key)
      end

      options
    end

    def configuration_set_for(mail)
      mail.header["X-SES-CONFIGURATION-SET"]&.value || @settings[:configuration_set_name]
    end
end

ActionMailer::Base.add_delivery_method :ses, SesDeliveryMethod

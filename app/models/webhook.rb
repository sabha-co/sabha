require "net/http"
require "uri"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 300.seconds
  MAX_REPLY_BODY_SIZE = 10.megabytes
  ALLOWED_REPLY_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp
    video/mp4 video/quicktime video/webm
    audio/mpeg audio/mp4 audio/ogg audio/webm
    application/pdf
  ].freeze

  ResponseTooLarge = Class.new(StandardError)

  Response = Struct.new(:code, :message, :content_type, :body, keyword_init: true) do
    def success?
      code.to_i.between?(200, 299)
    end
  end

  belongs_to :user

  validates :url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/i, message: "must be a valid HTTP(S) URL" }
  validate :url_not_targeting_private_network

  private def url_not_targeting_private_network
    return if url.blank?

    SsrfProtection.resolve!(URI(url).host)
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  rescue SsrfProtection::Unresolvable
    errors.add(:url, "could not be resolved")
  rescue SsrfProtection::PrivateAddress
    errors.add(:url, "must not target private or internal networks")
  end

  def deliver_later(item, event, reply: false, base_url: "")
    event_name = Bot::EventPayload.event_name_for(item, event)
    payload = create_payload(item, event, base_url: base_url)

    Bot::WebhookJob.perform_later(self, event_name, payload, item.try(:room), reply)
  end

  def deliver_now(item, event, reply: false, base_url: "")
    event_name = Bot::EventPayload.event_name_for(item, event)
    payload = create_payload(item, event, base_url: base_url)

    deliver(event_name, payload, item.try(:room), reply: reply)
  end

  def deliver(event_name, payload, room, reply: false)
    if reply
      deliver_with_reply(event_name, payload, room)
    else
      deliver_without_reply(event_name, payload)
    end
  end

  private
    def deliver_with_reply(event_name, payload, room)
      post(event_name, payload).tap do |response|
        if text = extract_text_from(response)
          receive_text_reply_to(room, text: text)
        elsif attachment = extract_attachment_from(response)
          receive_attachment_reply_to(room, attachment: attachment)
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      receive_text_reply_to room, text: "Failed to respond within #{ENDPOINT_TIMEOUT} seconds"
    rescue ResponseTooLarge
      receive_text_reply_to room, text: "Bot reply exceeded #{MAX_REPLY_BODY_SIZE / 1.megabyte}MB limit"
    end

    def deliver_without_reply(event_name, payload)
      post(event_name, payload).tap do |response|
        raise "Failed to deliver webhook to #{url}, response: #{response.code} #{response.message}" unless response.success?
      end
    end

    def post(event_name, payload)
      headers = { "Content-Type" => "application/json" }.merge(signature_headers(event_name, payload))
      request = Net::HTTP::Post.new(uri, headers).tap { |r| r.body = payload }

      body = String.new
      net_response = http.request(request) do |response|
        response.read_body do |chunk|
          body << chunk
          raise ResponseTooLarge if body.bytesize > MAX_REPLY_BODY_SIZE
        end
      end

      Response.new(
        code: net_response.code,
        message: net_response.message,
        content_type: net_response.content_type,
        body: body
      )
    end

    def signature_headers(event_name, payload)
      User::Bot::WebhookSigner.headers_for(bot: user, event_name: event_name, raw_body: payload)
    end

    def http
      resolved_ip = SsrfProtection.resolve!(uri.host)

      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = ENDPOINT_TIMEOUT
        http.read_timeout = ENDPOINT_TIMEOUT
        http.ipaddr = resolved_ip
      end
    end

    def uri
      @uri ||= URI(url)
    end

    def create_payload(item, event, base_url: "")
      Bot::EventPayload.build(item, event, bot: user, base_url: base_url).to_json
    end

    def extract_text_from(response)
      response.body.dup.force_encoding("UTF-8") if response.code == "200" && response.content_type.in?(%w[ text/html text/plain ])
    end

    def receive_text_reply_to(room, text:)
      room.messages.create!(body: text, creator: user).broadcast_create
    end

    def extract_attachment_from(response)
      return unless response.content_type && ALLOWED_REPLY_CONTENT_TYPES.include?(response.content_type)

      mime_type = Mime::Type.lookup(response.content_type)
      return unless mime_type

      ActiveStorage::Blob.create_and_upload! \
        io: StringIO.new(response.body), filename: "attachment.#{mime_type.symbol}", content_type: mime_type.to_s
    end

    def receive_attachment_reply_to(room, attachment:)
      room.messages.create_with_attachment!(attachment: attachment, creator: user).broadcast_create
    end
end

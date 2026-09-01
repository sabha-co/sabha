require "net/http"
require "uri"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 300.seconds

  class DeliveryError < StandardError; end

  belongs_to :user

  validates :url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/i, message: "must be a valid HTTP(S) URL" }
  validate :url_not_targeting_private_network

  private def url_not_targeting_private_network
    return if url.blank?

    RestrictedHTTP::PrivateNetworkGuard.resolve_public_ip!(URI(url).host)
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  rescue Surfguard::Unresolvable
    errors.add(:url, "could not be resolved")
  rescue RestrictedHTTP::PrivateNetworkGuard::Violation
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
    end

    def deliver_without_reply(event_name, payload)
      post(event_name, payload).tap do |response|
        raise Webhook::DeliveryError, "Failed to deliver webhook to #{url}, response: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
      end
    end

    def post(event_name, payload)
      headers = { "Content-Type" => "application/json" }.merge(signature_headers(event_name, payload))
      http.request Net::HTTP::Post.new(uri, headers).tap { |request| request.body = payload }
    end

    def signature_headers(event_name, payload)
      User::Bot::WebhookSigner.headers_for(bot: user, event_name: event_name, raw_body: payload)
    end

    def http
      resolved_ip = RestrictedHTTP::PrivateNetworkGuard.resolve_public_ip!(uri.host)

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
      if response.content_type && mime_type = Mime::Type.lookup(response.content_type)
        ActiveStorage::Blob.create_and_upload! \
          io: StringIO.new(response.body), filename: "attachment.#{mime_type.symbol}", content_type: mime_type.to_s
      end
    end

    def receive_attachment_reply_to(room, attachment:)
      room.messages.create_with_attachment!(attachment: attachment, creator: user).broadcast_create
    end
end

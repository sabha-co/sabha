require "net/http"
require "uri"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 300.seconds

  belongs_to :user

  validates :url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/i, message: "must be a valid HTTP(S) URL" }
  validate :url_not_targeting_private_network

  private def url_not_targeting_private_network
    return if url.blank?

    RestrictedHTTP::PrivateNetworkGuard.resolve(URI(url).host)
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  rescue Resolv::ResolvError
    errors.add(:url, "could not be resolved")
  rescue RestrictedHTTP::Violation
    errors.add(:url, "must not target private or internal networks")
  end

  def deliver_later(item, event, reply: false)
    payload = create_payload(item, event)

    Bot::WebhookJob.perform_later(self, payload, item.try(:room), reply)
  end

  def deliver_now(item, event, reply: false)
    payload = create_payload(item, event)

    deliver(payload, item.try(:room), reply: reply)
  end

  def deliver(payload, room, reply: false)
    if reply
      deliver_with_reply(payload, room)
    else
      deliver_without_reply(payload)
    end
  end

  private
    def deliver_with_reply(payload, room)
      post(payload).tap do |response|
        if text = extract_text_from(response)
          receive_text_reply_to(room, text: text)
        elsif attachment = extract_attachment_from(response)
          receive_attachment_reply_to(room, attachment: attachment)
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      receive_text_reply_to room, text: "Failed to respond within #{ENDPOINT_TIMEOUT} seconds"
    end

    def deliver_without_reply(payload)
      post(payload).tap do |response|
        raise "Failed to deliver webhook to #{url}, response: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
      end
    end

    def post(payload)
      http.request \
        Net::HTTP::Post.new(uri, "Content-Type" => "application/json").tap { |request| request.body = payload }
    end

    def http
      resolved_ip = RestrictedHTTP::PrivateNetworkGuard.resolve(uri.host)

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

    def create_payload(item, event)
      if item.is_a?(Message)
        message_payload(item, event)
      elsif item.is_a?(Boost)
        boost_payload(item, event)
      elsif item.is_a?(User)
        user_payload(item, event)
      else
        {}.to_json
      end
    end

    def message_payload(message, event)
      {
        event:   "message_#{event}",
        user:    user_to_api(message.creator),
        room:    room_to_api(message.room),
        message: message_to_api(message)
      }.to_json
    end

    def boost_payload(boost, event)
      {
        event:   "boost_#{event}",
        user:    user_to_api(boost.booster),
        room:    room_to_api(boost.message.room),
        message: message_to_api(boost.message),
        boost:   { id: boost.id, body: boost.content }
      }.to_json
    end

    def user_payload(user, event)
      {
        event:   "user_#{event}",
        user:    user_to_api(user)
      }.to_json
    end

    def room_to_api(room)
      {
        id: room.id,
        name: room.name,
        type: room.class.name.demodulize,
        members: room.memberships.visible.count,
        has_bot: user.member_of?(room),
        path: room_bot_messages_path(room)
      }
    end

    def message_to_api(message)
      {
        id: message.id,
        body: { html: message.body.body, plain: message.plain_text_body },
        has_attachment: message.attachment?,
        attachment: attachment_to_api(message),
        mentionees: message.mentionees.map { |m| { id: m.id, name: m.name } },
        path: message_path(message)
      }
    end

    def attachment_to_api(message)
      return nil unless message.attachment?

      blob = message.attachment.blob
      {
        url: blob_url(blob),
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size
      }
    end

    def blob_url(blob)
      Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    end

    def user_to_api(user)
      {
        id: user.id,
        name: user.name,
        path: user_path(user)
      }
    end

    def message_path(message)
      Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    end

    def room_bot_messages_path(room)
      Rails.application.routes.url_helpers.room_bot_messages_path(room, user.bot_key)
    end

    def user_path(user)
      Rails.application.routes.url_helpers.user_path(user)
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

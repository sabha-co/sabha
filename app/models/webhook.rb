require "net/http"
require "uri"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 300.seconds

  belongs_to :user

  enum receives: %w[ mentions everything ].index_by(&:itself), _prefix: :receives

  scope :receiving_mentions, -> { where(receives: :mentions) }
  scope :receiving_everything, -> { where(receives: :everything) }

  def cares_about?(item, event)
    if receives_mentions?
       event == :created && item.is_a?(Message) && item.mentionees.include?(user)
    else
      true
    end
  end

  def deliver_later(item, event)
    payload = create_payload(item, event)

    Bot::WebhookJob.perform_later(self, payload, item.try(:room))
  end

  def deliver_now(item, event)
    payload = create_payload(item, event)

    deliver(payload, item.try(:room))
  end

  def deliver(payload, room)
    if receives_mentions?
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
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = ENDPOINT_TIMEOUT
        http.read_timeout = ENDPOINT_TIMEOUT
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
        mentionees: message.mentionees.map { |m| { id: m.id, name: m.name } },
        path: message_path(message)
      }
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
      response.body.force_encoding("UTF-8") if response.code == "200" && response.content_type.in?(%w[ text/html text/plain ])
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

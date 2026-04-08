module Bot::EventPayload
  def self.build(item, event, bot:, base_url: "")
    urls = UrlBuilder.new(base_url, bot.bot_key)

    if item.is_a?(Message)
      {
        event:   "message_#{event}",
        user:    urls.user_to_api(item.creator),
        room:    urls.room_to_api(item.room, bot_is_member: bot.member_of?(item.room)),
        message: urls.message_to_api(item)
      }
    elsif item.is_a?(Boost)
      {
        event:   "boost_#{event}",
        user:    urls.user_to_api(item.booster),
        room:    urls.room_to_api(item.message.room, bot_is_member: bot.member_of?(item.message.room)),
        message: urls.message_to_api(item.message),
        boost:   { id: item.id, body: item.content }
      }
    elsif item.is_a?(User)
      {
        event:   "user_#{event}",
        user:    urls.user_to_api(item)
      }
    else
      {}
    end
  end

  class UrlBuilder
    def initialize(base_url, bot_key)
      @base_url = base_url
      @bot_key = bot_key
    end

    def room_to_api(room, bot_is_member: false)
      {
        id: room.id,
        name: room.name,
        type: room.class.name.demodulize,
        members: room.memberships.visible.count,
        has_bot: bot_is_member,
        messages_url: absolute_url(routes.room_bot_messages_path(room, @bot_key))
      }
    end

    def message_to_api(message)
      {
        id: message.id,
        body: { html: message.body.body, plain: message.plain_text_body },
        has_attachment: message.attachment?,
        attachment: attachment_to_api(message),
        mentionees: message.mentionees.map { |m| { id: m.id, name: m.name } },
        url: absolute_url(routes.room_at_message_path(message.room, message)),
        created_at: message.created_at.iso8601,
        updated_at: message.updated_at.iso8601,
        thread: thread_to_api(message)
      }
    end

    def user_to_api(user)
      {
        id: user.id,
        name: user.name,
        role: user.role,
        url: absolute_url(routes.user_path(user))
      }
    end

    private
      def thread_to_api(message)
        return nil unless message.room.thread?
        { id: message.room.id, parent_message_id: message.room.parent_message_id }
      end

      def attachment_to_api(message)
        return nil unless message.attachment?

        blob = message.attachment.blob
        {
          url: blob.url(expires_in: 1.hour),
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size
        }
      end

      def routes
        Rails.application.routes.url_helpers
      end

      def absolute_url(path)
        "#{@base_url}#{path}"
      end
  end
end

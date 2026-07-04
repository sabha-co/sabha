# Builds the WebPush payload shape (title / body / path) for a message in a
# room. Routing lives on `Message`; this class is payload-only.
class Room::MessagePusher
  attr_reader :room, :message

  def self.payload_for(room:, message:)
    new(room: room, message: message).build_payload
  end

  def initialize(room:, message:)
    @room, @message = room, message
  end

  def build_payload
    if room.direct?
      build_direct_payload
    else
      build_shared_payload
    end
  end

  private
    def build_direct_payload
      {
        title: message.creator.name,
        body: message.plain_text_body,
        path: push_path
      }
    end

    def build_shared_payload
      {
        title: room.display_name,
        body: "#{message.creator.name}: #{message.plain_text_body}",
        path: push_path
      }
    end

    def push_path
      helpers = Rails.application.routes.url_helpers

      if post = message.forum_post
        if post.opening_message?(message)
          helpers.forum_post_path(post.slug)
        else
          helpers.forum_post_path(post.slug, message_id: message.id)
        end
      elsif room.thread? && room.parent_message
        helpers.room_at_message_path(room.parent_message.room, room.parent_message)
      else
        helpers.room_path(room)
      end
    end
end

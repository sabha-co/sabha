# Builds the WebPush payload shape (title / body / path) for a message in a
# channel. Routing lives on `Message`; this class is payload-only.
class Channel::MessagePusher
  attr_reader :channel, :message

  def self.payload_for(channel:, message:)
    new(channel: channel, message: message).build_payload
  end

  def initialize(channel:, message:)
    @channel, @message = channel, message
  end

  def build_payload
    if channel.direct?
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
        title: channel.display_name,
        body: "#{message.creator.name}: #{message.plain_text_body}",
        path: push_path
      }
    end

    def push_path
      helpers = Rails.application.routes.url_helpers

      if post = message.forum_post
        message_id = message.id unless post.opening_message?(message)
        helpers.channel_path(post.parent_channel, post: post.slug, message_id:)
      elsif channel.thread? && channel.parent_message
        helpers.channel_at_message_path(channel.parent_message.channel, channel.parent_message)
      else
        helpers.channel_path(channel)
      end
    end
end

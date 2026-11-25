module MessagesHelper
  def edit_message_in_channel_path(channel, message)
    channel ? edit_channel_message_path(channel, message) : edit_message_path(message)
  end

  def message_in_channel_path(channel, message)
    channel ? channel_message_path(channel, message) : message_path(message)
  end

  def message_permalink_path(message)
    message_permalink(message, only_path: true)
  end

  def message_permalink_url(message)
    message_permalink(message, only_path: false)
  end

  def message_area_tag(channel, id: "message-area", presence: true, &)
    controllers = [ "messages", ("presence" if presence), "drop-target" ].compact.join(" ")
    actions = [ messages_actions, drop_target_actions ]
    actions << presence_actions if presence

    data = {
      controller: controllers,
      action: actions.join(" "),
      messages_first_of_day_class: "message--first-of-day",
      messages_first_unread_class: "message__new-separator",
      messages_formatted_class: "message--formatted",
      messages_me_class: "message--me",
      messages_mentioned_class: "message--mentioned",
      messages_mentioned_unread_class: "message--mentioned-unread",
      messages_threaded_class: "message--threaded",
      messages_loading_up_class: "message--loading-up",
      messages_loading_down_class: "message--loading-down",
      messages_page_url_value: channel_messages_url(channel)
    }

    data[:presence_channel_id_value] = channel.id if presence

    tag.div id: id, class: "message-area", contents: true, data: data, &
  end

  def messages_tag(channel, refresh: true, &)
    controllers = refresh ? "maintain-scroll refresh-channel" : "maintain-scroll"
    actions = refresh ? [ maintain_scroll_actions, refresh_channel_actions ].join(" ") : maintain_scroll_actions

    data = {
      controller: controllers,
      action: actions,
      messages_target: "messages"
    }

    if refresh
      data[:refresh_channel_loaded_at_value] = channel.updated_at.to_fs(:epoch)
      data[:refresh_channel_url_value] = channel_refresh_url(channel)
      data[:refresh_channel_first_unread_class] = "message__new-separator"
    end

    tag.div id: dom_id(channel, :messages), class: "messages", aria: { live: "polite", relevant: "additions" }, data: data, &
  end

  # True when this message was written by the forum post's original poster — the
  # opening message or any later reply by the same author. The post records its
  # creator (the OP), so this is deterministic and O(1) — cache-safe. Non-post
  # messages are never OP.
  def forum_op?(message)
    message.channel.post? && message.creator_id == message.channel.creator_id
  end

  # True for the single opening message of a forum post — its earliest message,
  # which carries the post body and gets the roomier "question" hero treatment.
  # Memoized per post so a message list resolves it once, not per message; the
  # "which message opens the post" query lives on Channels::Post#opening_message_id.
  def forum_opening_message?(message)
    channel = message.channel
    return false unless channel.post?

    (@forum_opening_ids ||= {})[channel.id] ||= channel.opening_message_id
    @forum_opening_ids[channel.id] == message.id
  end

  def message_tag(message, is_unread: false, composer_id: "composer", &)
    message_timestamp_milliseconds = message.created_at.to_fs(:epoch)

    data = {
      user_id: message.creator_id,
      message_id: message.id,
      message_timestamp: message_timestamp_milliseconds,
      message_updated_at: message.updated_at.to_fs(:epoch),
      sort_value: message_timestamp_milliseconds,
      unread: is_unread || nil,
      messages_target: "message",
      search_results_target: "message",
      refresh_channel_target: "message",
      inbox_target: "message"
    }

    if message.repliable?
      data[:controller] = "reply"
      data[:reply_composer_outlet] = "##{composer_id}"
    end

    data[:message_event] = true if message.event?

    tag.div id: dom_id(message),
      class: class_names("message", "message--event": message.event?, "message--welcome": message.welcome?, "message--emoji": !message.event? && !message.welcome? && message.plain_text_body.all_emoji?, "message--forum-opening": forum_opening_message?(message)),
      data: data, &
  rescue Exception => e
    Sentry.capture_exception(e, extra: { message: message })
    Rails.logger.error "Exception while rendering message #{message.class.name}##{message.id}, failed with: #{e.class} `#{e.message}`"

    render "messages/unrenderable"
  end

  def message_timestamp(message, style: :time, **attributes)
    timestamp = local_datetime_tag message.created_at, style: style, **attributes
    timestamp += tag.span("(edited)", class: "message__edited") if message.edited?
    timestamp
  end

  def message_presentation(message)
    case message.content_type
    when "attachment"
      message_attachment_presentation(message)
    when "sound"
      message_sound_presentation(message)
    else
      # sanitize: false because the content already passed through ActionText's
      # sanitizer (with SabhaActionTextSafelist's extensions). Letting auto_link
      # re-sanitize with the default Rails safelist strips details/summary/
      # turbo-frame and our popup data-* attributes from rendered mentions.
      # When sanitize is disabled rails_autolink doesn't mark the result safe,
      # so we do it ourselves.
      auto_link(h(ContentFilters.text_message_presentation_filters.apply(message.body.body)), sanitize: false, html: { target: "_blank" }).html_safe
    end
  rescue Exception => e
    Sentry.capture_exception(e, extra: { message: message })
    Rails.logger.error "Exception while generating message representation for #{message.class.name}##{message.id}, failed with: #{e.class} `#{e.message}`"

    ""
  end

  def message_cache_key(message, channel_id: nil, is_first_unread_message: false, is_unread: false, is_parent: false, show_channel_name: false, composer_id: "composer", forum_replies_count: nil)
    [
      # Bump this version when message presentation changes what it emits but the
      # digestor can't see it — e.g. the opengraph embed partial, which ActionText
      # renders by name rather than through a render call the digestor follows.
      "presentation-v2",
      message,
      channel_id,
      message.bookmarked_by?(Current.user),
      message.creator,
      is_first_unread_message,
      is_unread,
      is_parent,
      show_channel_name,
      composer_id,
      message.thread_fingerprint,
      forum_replies_count
    ]
  end

  private
    # Shared resolver for message_permalink_path / _url — the same three-branch
    # decision (forum post / chat thread / plain channel). only_path toggles between
    # a path and a full URL, the sole difference between the two public helpers.
    def message_permalink(message, only_path:)
      channel = message.channel
      if post = message.forum_post
        message_id = message.id unless forum_opening_message?(message)
        channel_url(post.parent_channel, post: post.slug, message_id:, only_path:)
      elsif channel.thread? && (parent = channel.parent_message)
        channel_at_message_url(parent.channel, parent, only_path:)
      else
        channel_at_message_url(channel, message, only_path:)
      end
    end

    def messages_actions
      "turbo:before-stream-render@document->messages#beforeStreamRender keydown.up@document->messages#editMyLastMessage"
    end

    def maintain_scroll_actions
      "turbo:before-stream-render@document->maintain-scroll#beforeStreamRender"
    end

    def refresh_channel_actions
      "visibilitychange@document->refresh-channel#visibilityChanged online@window->refresh-channel#online"
    end

    def presence_actions
      "visibilitychange@document->presence#visibilityChanged"
    end

    def message_attachment_presentation(message)
      Messages::AttachmentPresentation.new(message, context: self).render
    end

    def message_sound_presentation(message)
      sound = message.sound

      tag.div class: "sound", data: { controller: "sound", action: "messages:play->sound#play", sound_url_value: asset_path(sound.asset_path) } do
        play_button + (sound.image ? sound_image_tag(sound.image) : sound.text)
      end
    end

    def play_button
      tag.button "🔊", class: "btn btn--plain", data: { action: "sound#play" }
    end

    def sound_image_tag(image)
      image_tag image.asset_path, width: image.width, height: image.height, class: "align--middle"
    end

    def message_author_title(author)
      [ author.name, author.bio ].compact_blank.join(" – ")
    end
end

module ChannelsHelper
  def link_to_channel(channel, **attributes, &)
    link_to channel_path(channel), **attributes, data: {
      channels_list_target: "channel", channel_id: channel.id, badge_dot_target: "unread"
    }.merge(attributes.delete(:data) || {}), &
  end

  def link_to_edit_channel(channel)
    count = channel.active_member_count
    link_to \
      edit_channel_path(channel),
      class: "btn",
      style: "view-transition-name: edit-channel-#{channel.id}",
      data: { channel_id: channel.id } do
        image_tag("person.svg", aria: { hidden: "true" }) +
        tag.span(number_with_delimiter(count), class: "hide-on-mobile") +
        tag.span(round_for_mobile(count), class: "hide-on-desktop")
    end
  end

  def link_back_to_last_channel_visited
    if controller.respond_to?(:last_channel_visited)
      # Use the controller's method if available
      if last_channel = controller.last_channel_visited
        link_back_to channel_path(last_channel)
      else
        link_back_to root_path
      end
    else
      # Fallback implementation if controller method is not available
      last_channel_id = cookies[:last_channel]
      if last_channel_id.present? && (last_channel = Channel.find_by(id: last_channel_id))
        link_back_to channel_path(last_channel)
      else
        link_back_to root_path
      end
    end
  end

  def button_to_delete_channel(channel, url: nil)
    if channel.is_a?(Channels::Direct)
      confirm_message = "Are you sure you want to delete this conversation and all messages in it? This can't be undone."
      button_label = "Delete conversation"
    else
      confirm_message = "Are you sure you want to delete this channel and all messages in it? This can't be undone."
      button_label = channel_display_name(channel)
    end

    button_to channel, method: :delete, class: "btn btn--negative max-width", aria: { label: "Delete #{channel.name}" },
        data: { turbo_confirm: confirm_message } do
      image_tag("trash.svg", aria: { hidden: "true" }, size: 20) +
      tag.span(button_label, class: "overflow-ellipsis")
    end
  end

  def button_to_jump_to_newest_message
    tag.button \
        class: "message-area__return-to-latest btn",
        data: { action: "messages#returnToLatest", messages_target: "latest" },
        hidden: true do
      image_tag("arrow-down.svg", aria: { hidden: "true" }, size: 20) +
      tag.span("Jump to newest message", class: "for-screen-reader")
    end
  end

  def submit_channel_button_tag
    button_tag class: "btn btn--reversed txt-large center", type: "submit" do
      image_tag("check.svg", aria: { hidden: "true" }, size: 20) +
      tag.span("Save", class: "for-screen-reader")
    end
  end

  def composer_form_tag(channel, form_id: "composer", message_area_id: "message-area", connection_monitor: true, &)
    form_with model: Message.new, url: channel_messages_path(channel),
      id: form_id, class: "margin-block flex-item-grow contain", data: composer_data_options(channel, message_area_id: message_area_id, connection_monitor: connection_monitor), &
  end

  def channel_type_indicator(channel)
    if channel.is_a?(Channels::Closed)
      icon_tag "lock"
    elsif channel.is_a?(Channels::Forum)
      icon_tag "message-log"
    elsif !channel.is_a?(Channels::Direct)
      "#"
    end
  end

  def channel_display_name(channel, for_user: Current.user)
    channel.display_name(for_user: for_user)
  end

  def edit_channel_path(channel)
    case channel
    when Channels::Direct then edit_channels_direct_path(channel)
    when Channels::Open   then edit_channels_open_path(channel)
    when Channels::Closed then edit_channels_closed_path(channel)
    when Channels::Forum  then edit_channels_forum_path(channel)
    when Channels::Thread then edit_channels_thread_path(channel)
    else raise ArgumentError, "Unknown channel type: #{channel.class}"
    end
  end

  private
    def composer_data_options(channel, message_area_id: "message-area", connection_monitor: true)
      {
        controller: "composer drop-target",
        action: composer_data_actions(connection_monitor: connection_monitor),
        composer_messages_outlet: "##{message_area_id}",
        composer_toolbar_class: "composer--rich-text", composer_channel_id_value: channel.id,
        composer_direct_upload_url_value: rails_direct_uploads_url,
        composer_everyone_confirm_threshold_value: Rails.configuration.x.everyone_mention.confirm_threshold,
        composer_everyone_member_count_value: (channel.active_member_count if channel.is_a?(Channels::Open)) || 0,
        composer_everyone_capped_value: channel.is_a?(Channels::Open) && channel.everyone_mention_over_ceiling?
      }
    end

    def composer_data_actions(connection_monitor: true)
      drag_and_drop_actions = "drop-target:drop@window->composer#dropFiles"

      attachment_actions = "lexxy:file-accept->composer#preventAttachment"
      attachment_actions += " refresh-channel:online@window->composer#online" if connection_monitor

      remaining_actions =
        "typing-notifications#stop paste->composer#pasteFiles turbo:submit-end->composer#submitEnd"
      remaining_actions += " refresh-channel:offline@window->composer#offline" if connection_monitor

      [ drop_target_actions, drag_and_drop_actions, attachment_actions, remaining_actions ].join(" ")
    end

    # round_for_mobile(123)             # => "123"
    # round_for_mobile(1234)            # => "1.2k"
    # round_for_mobile(12345)           # => "12k"
    # round_for_mobile(12345678)        # => "12M"
    def round_for_mobile(number)
      number_to_human(number,
                      precision: number < 10_000 ? 1 : 0,
                      significant: false,
                      format: "%n%u",
                      units: { thousand: "k", million: "M", billion: "B" })
    end
end

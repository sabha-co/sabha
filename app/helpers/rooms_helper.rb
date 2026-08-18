module RoomsHelper
  def link_to_room(room, **attributes, &)
    link_to room_path(room), **attributes, data: {
      rooms_list_target: "room", room_id: room.id, badge_dot_target: "unread"
    }.merge(attributes.delete(:data) || {}), &
  end

  def link_to_room_roster(room)
    link_to \
      room_roster_path(room),
      class: "btn",
      aria: { label: "Who's in #{room_display_name(room)}" },
      data: { turbo_frame: "thread_panel_frame", room_id: room.id } do
        icon_tag("info", style: "--icon-size: 18px") +
        tag.span("Room details", class: "for-screen-reader")
    end
  end

  def browse_room_type_label(room)
    case room
    when Rooms::Closed then "Private"
    when Rooms::Forum then "Forum"
    else "Open"
    end
  end

  def dm_presence_label(status)
    case status
    when :active then "Here now"
    when :away then "Away"
    else "Offline"
    end
  end

  def direct_member_status(user)
    Membership.activity_statuses_for([ user.id ])[user.id]
  end

  def link_back_to_last_room_visited
    if controller.respond_to?(:last_room_visited)
      # Use the controller's method if available
      if last_room = controller.last_room_visited
        link_back_to room_path(last_room)
      else
        link_back_to root_path
      end
    else
      # Fallback implementation if controller method is not available
      last_room_id = cookies[:last_room]
      if last_room_id.present? && (last_room = Room.find_by(id: last_room_id))
        link_back_to room_path(last_room)
      else
        link_back_to root_path
      end
    end
  end

  def button_to_delete_room(room, url: nil)
    if room.is_a?(Rooms::Direct)
      confirm_message = "Are you sure you want to delete this conversation and all messages in it? This can't be undone."
      aria_label = "Delete conversation"
    else
      confirm_message = "Are you sure you want to delete this room and all messages in it? This can't be undone."
      aria_label = "Delete #{room_display_name(room)}"
    end

    button_to "Delete", room, method: :delete, class: "btn settings-chip-btn settings-chip-btn--negative flex-item-no-shrink",
        aria: { label: aria_label }, data: { turbo_confirm: confirm_message }
  end

  def button_to_jump_to_newest_message
    tag.button \
        class: "message-area__return-to-latest btn",
        data: { action: "messages#returnToLatest", messages_target: "latest" },
        hidden: true do
      tag.span("Jump to newest") + icon_tag("arrow-down", style: "--icon-size: 13px")
    end
  end

  def submit_room_button_tag(label = "Save changes")
    button_tag label, class: "btn settings-save", type: "submit"
  end

  def composer_form_tag(room, form_id: "composer", message_area_id: "message-area", connection_monitor: true, &)
    form_with model: Message.new, url: room_messages_path(room),
      id: form_id, class: "margin-block flex-item-grow contain", data: composer_data_options(room, message_area_id: message_area_id, connection_monitor: connection_monitor), &
  end

  def room_type_indicator(room)
    if room.is_a?(Rooms::Closed)
      icon_tag "lock"
    elsif room.is_a?(Rooms::Forum)
      icon_tag "message-log"
    elsif !room.is_a?(Rooms::Direct)
      "#"
    end
  end

  def room_display_name(room, for_user: Current.user)
    room.display_name(for_user: for_user)
  end

  # "Message #general" for channels, "Message Kevin" for 1:1 DMs; group DMs
  # fall back to the member-list display name.
  def composer_placeholder(room)
    if room.direct?
      others = room.users.without(Current.user)
      name = others.one? ? others.first.name.split(" ").first : room_display_name(room)
      "Message #{name}"
    else
      prefix = room.is_a?(Rooms::Open) ? "#" : ""
      "Message #{prefix}#{room_display_name(room)}"
    end
  end

  def edit_room_path(room)
    case room
    when Rooms::Direct then edit_rooms_direct_path(room)
    when Rooms::Open   then edit_rooms_open_path(room)
    when Rooms::Closed then edit_rooms_closed_path(room)
    when Rooms::Forum  then edit_rooms_forum_path(room)
    when Rooms::Thread then edit_rooms_thread_path(room)
    else raise ArgumentError, "Unknown room type: #{room.class}"
    end
  end

  private
    def composer_data_options(room, message_area_id: "message-area", connection_monitor: true)
      {
        controller: "composer drop-target",
        action: composer_data_actions(connection_monitor: connection_monitor),
        composer_messages_outlet: "##{message_area_id}",
        composer_toolbar_class: "composer--rich-text", composer_room_id_value: room.id,
        composer_direct_upload_url_value: rails_direct_uploads_url,
        composer_everyone_confirm_threshold_value: Rails.configuration.x.everyone_mention.confirm_threshold,
        composer_everyone_member_count_value: (room.active_member_count if room.is_a?(Rooms::Open)) || 0,
        composer_everyone_capped_value: room.is_a?(Rooms::Open) && room.everyone_mention_over_ceiling?
      }
    end

    def composer_data_actions(connection_monitor: true)
      drag_and_drop_actions = "drop-target:drop@window->composer#dropFiles"

      attachment_actions = "lexxy:file-accept->composer#preventAttachment"
      attachment_actions += " refresh-room:online@window->composer#online" if connection_monitor

      remaining_actions =
        "typing-notifications#stop paste->composer#pasteFiles turbo:submit-end->composer#submitEnd"
      remaining_actions += " refresh-room:offline@window->composer#offline" if connection_monitor

      [ drop_target_actions, drag_and_drop_actions, attachment_actions, remaining_actions ].join(" ")
    end
end

module RoomsHelper
  def link_to_room(room, **attributes, &)
    link_to room_path(room), **attributes, data: {
      rooms_list_target: "room", room_id: room.id, badge_dot_target: "unread"
    }.merge(attributes.delete(:data) || {}), &
  end

  def link_to_edit_room(room)
    count = room.active_member_count
    link_to \
      edit_room_path(room),
      class: "btn",
      style: "view-transition-name: edit-room-#{room.id}",
      data: { room_id: room.id } do
        image_tag("person.svg", aria: { hidden: "true" }) +
        tag.span(number_with_delimiter(count), class: "hide-on-mobile") +
        tag.span(round_for_mobile(count), class: "hide-on-desktop")
    end
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
      button_label = "Delete conversation"
    else
      confirm_message = "Are you sure you want to delete this room and all messages in it? This can't be undone."
      button_label = room_display_name(room)
    end

    button_to room, method: :delete, class: "btn btn--negative max-width", aria: { label: "Delete #{room.name}" },
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

  def submit_room_button_tag
    button_tag class: "btn btn--reversed txt-large center", type: "submit" do
      image_tag("check.svg", aria: { hidden: "true" }, size: 20) +
      tag.span("Save", class: "for-screen-reader")
    end
  end

  def composer_form_tag(room, form_id: "composer", message_area_id: "message-area", connection_monitor: true, &)
    form_with model: Message.new, url: room_messages_path(room),
      id: form_id, class: "margin-block flex-item-grow contain", data: composer_data_options(room, message_area_id: message_area_id, connection_monitor: connection_monitor), &
  end

  def room_type_indicator(room)
    if room.is_a?(Rooms::Closed)
      icon_tag "lock"
    elsif room.is_a?(Rooms::Forum)
      icon_tag "board"
    elsif !room.is_a?(Rooms::Direct)
      "#"
    end
  end

  def room_display_name(room, for_user: Current.user)
    room.display_name(for_user: for_user)
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
        composer_direct_upload_url_value: rails_direct_uploads_url
      }
    end

    def composer_data_actions(connection_monitor: true)
      drag_and_drop_actions = "drop-target:drop@window->composer#dropFiles"

      trix_attachment_actions = "trix-file-accept->composer#preventAttachment"
      trix_attachment_actions += " refresh-room:online@window->composer#online" if connection_monitor

      remaining_actions =
        "typing-notifications#stop paste->composer#pasteFiles turbo:submit-end->composer#submitEnd"
      remaining_actions += " refresh-room:offline@window->composer#offline" if connection_monitor

      [ drop_target_actions, drag_and_drop_actions, trix_attachment_actions, remaining_actions ].join(" ")
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

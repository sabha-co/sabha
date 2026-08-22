module Users::SidebarHelper
  def has_unreads?
    return unless Current.user.present?

    Current.user.memberships.unread.any?
  end

  def sidebar_turbo_frame_tag(src: nil, &block)
    # A lazy (src-driven) frame shows a cold-start skeleton until its rooms land;
    # the content frame (block form) renders the real list.
    body = block ? capture(&block) : (render("users/sidebars/skeleton") if src)

    turbo_frame_tag :user_sidebar, src: src, target: "_top", data: {
      turbo_permanent: true,
      controller: "rooms-list read-rooms turbo-frame",
      rooms_list_unread_class: "unread",
      rooms_list_badge_class: "badge",
      rooms_list_stream_value: Current.account&.signed_room_list_stream_name,
      action: "turbo:load@window->rooms-list#markCurrent presence:present@window->rooms-list#read read-rooms:read->rooms-list#read read-rooms:unread->rooms-list#markUnread turbo:frame-load->rooms-list#loaded refresh-room:visible@window->turbo-frame#reload".html_safe # otherwise -> is escaped
    } do
      body
    end
  end
end

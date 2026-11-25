module Users::SidebarHelper
  def has_unreads?
    return unless Current.user.present?

    Current.user.memberships.unread.any?
  end

  def sidebar_turbo_frame_tag(src: nil, &)
    turbo_frame_tag :user_sidebar, src: src, target: "_top", data: {
      controller: "channels-list read-channels turbo-frame",
      channels_list_unread_class: "unread",
      channels_list_badge_class: "badge",
      channels_list_stream_value: Current.account&.signed_channel_list_stream_name,
      action: "presence:present@window->channels-list#read read-channels:read->channels-list#read read-channels:unread->channels-list#markUnread turbo:frame-load->channels-list#loaded refresh-channel:visible@window->turbo-frame#reload".html_safe # otherwise -> is escaped
    }, &
  end
end

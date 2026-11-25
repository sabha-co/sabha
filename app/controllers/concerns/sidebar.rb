module Sidebar
  extend ActiveSupport::Concern

  SIDEBAR_SECTIONS = [ :starred_channels, :shared_channels ].freeze

  def set_sidebar_memberships
    sidebar = SidebarMemberships.new(Current.user)

    @direct_memberships   = sidebar.direct
    @direct_channel_members  = sidebar.direct_channel_members(@direct_memberships)
    @starred_memberships  = sidebar.starred
    @shared_memberships   = sidebar.shared
  end

  def broadcast_sidebar_channel_added(user, channel, formats: nil)
    membership = user.memberships.find_by(channel: channel)
    return unless membership

    list_name = membership.sidebar_list_name
    html = render_to_string(partial: "users/sidebars/channels/shared", formats: formats || [ :html ], locals: { list_name:, membership: membership })
    broadcast_append_to user, :channels, target: list_name, html: html, attributes: { maintain_scroll: true }
  end

  def broadcast_sidebar_channel_removed(streamable, channel)
    SIDEBAR_SECTIONS.each do |list_name|
      broadcast_remove_to streamable, :channels, target: [ channel, helpers.dom_prefix(list_name, :list_node) ]
    end
  end
end
